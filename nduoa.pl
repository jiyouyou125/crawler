#!/usr/bin/perl
BEGIN{unshift(@INC, $1) if ($0=~m/(.+)\//);}
use strict;
use warnings;

use HTML::Entities;
use AMMS::Util;
use AMMS::AppFinder;
use AMMS::Downloader;
use AMMS::NewAppExtractor;
use AMMS::UpdatedAppExtractor;

my $task_type   = $ARGV[0];
my $task_id     = $ARGV[1];
my $conf_file   = $ARGV[2];

my $market      = 'www.nduoa.com';
my $url_base    = 'http://www.nduoa.com';
my $downloader  = new AMMS::Downloader;

my %category_mapping=(
        "\x{65E5}\x{5E38}\x{5B9E}\x{7528}"=>22,
        "\x{7CFB}\x{7EDF}\x{7BA1}\x{7406}"=>22,
        "\x{901A}\x{8BAF}\x{7F51}\x{7EDC}"=>4,
        "\x{5F71}\x{97F3}\x{62CD}\x{7167}"=>"7,15", 
        "\x{793E}\x{533A}\x{8D44}\x{8BAF}"=>"18,14",
        "\x{5730}\x{56FE}\x{5BFC}\x{822A}"=>"13,21",
        "\x{4E3B}\x{9898}\x{7F8E}\x{5316}"=>12, 
        "\x{5B66}\x{4E60}\x{5A31}\x{4E50}"=>"5,6", 
        "\x{533B}\x{7597}\x{4FDD}\x{5065}"=>"9,10", 
        "\x{7535}\x{5B50}\x{4E66}\x{7C4D}"=>1, 
        "\x{4F53}\x{80B2}\x{7ADE}\x{901F}"=>814, 
        "\x{7ECF}\x{8425}\x{7B56}\x{7565}"=>815, 
        "\x{52A8}\x{4F5C}\x{5192}\x{9669}"=>800,
        "\x{68CB}\x{724C}\x{76CA}\x{667A}"=>803, 
        "\x{98DE}\x{884C}\x{5C04}\x{51FB}"=>821, 
        "\x{8DA3}\x{5473}\x{4F11}\x{95F2}"=>818,
        "\x{6A21}\x{62DF}\x{5668}"=>813, 
                );
die "\nplease check config parameter\n" unless init_gloabl_variable( $conf_file );

if( $task_type eq 'find_app' )##find new android app
{
    my $AppFinder   = new AMMS::AppFinder('MARKET'=>$market,'TASK_TYPE'=>$task_type);
    $AppFinder->addHook('extract_page_list', \&extract_page_list);
    $AppFinder->addHook('extract_app_from_feeder', \&extract_app_from_feeder);
    $AppFinder->run($task_id);
}
elsif( $task_type eq 'new_app' )##download new app info and apk
{
    my $NewAppExtractor= new AMMS::NewAppExtractor('MARKET'=>$market,'TASK_TYPE'=>$task_type);
    $NewAppExtractor->addHook('extract_app_info', \&extract_app_info);
    $NewAppExtractor->run($task_id);
}
elsif( $task_type eq 'update_app' )##download updated app info and apk
{
    my $UpdatedAppExtractor= new AMMS::UpdatedAppExtractor('MARKET'=>$market,'TASK_TYPE'=>$task_type);
    $UpdatedAppExtractor->addHook('extract_app_info', \&extract_app_info);
    $UpdatedAppExtractor->run($task_id);
}

exit;

sub extract_app_info
{
    my $tree;
    my @node;
    my @tags;
    my ($worker, $hook, $webpage, $app_info) = @_;

    eval {
#utf8::encode($webpage);

        $tree = HTML::TreeBuilder->new; # empty tree
        $tree->ignore_unknown(0);
        $tree->parse($webpage);
        
        @node= $tree->look_down("_tag","div","class","i_icon");
        $app_info->{icon}=($node[0]->content_list)[0]->attr("src");
        @node= $tree->look_down("class","app_name");
        $app_info->{app_name}=$node[0]->as_text;
        @node= $tree->look_down("class","app_size");
        $app_info->{size}=0;
        my $size=$1 if $node[0]->as_text=~/\x{FF1A}(.*)/;
        $size=$1*1024 if $size=~/([\d\.]+)M/i;
        $app_info->{size}=int($size*1024);
        @node= $tree->look_down("class","app_version");
        $app_info->{current_version}=$1 if $node[0]->as_text=~/\x{FF1A}(.*)/;
        @node= $tree->look_down("class","app_author");
        $app_info->{author}=$1 if $node[0]->as_text=~/\x{FF1A}(.*)/;
        @node= $tree->look_down("class","time");
        if ($node[0]->as_text=~/(\d+).*?([\d-]+)/){
            $app_info->{total_install_times}=$1;
            $app_info->{last_update}=$2;
        }
        @node= $tree->look_down("class","hidd_p");
        my $html = $node[0]->as_HTML;
        my @array= $html =~ /([\d\.]+)/g;
        my @sort_array= sort @array;
        $app_info->{min_os_version}=$sort_array[0];
        $app_info->{max_os_version}=$sort_array[$#sort_array];
        $html   = $node[1]->as_HTML;
        @array= $html =~ /([\dx]+)/g;
        $app_info->{resolution}=join ',', @array;

        @node= $tree->look_down("_tag","span","class","p_stars");
        $html=$node[0]->as_HTML;
        @array=$html=~/"stared"/g;
        $app_info->{official_rating_stars}= scalar(@array);
        $app_info->{official_rating_stars} += 0.5 if $html=~/"half"/g;
        $app_info->{official_rating_times}=0;

        @node= $tree->look_down("_tag","div","class","dt_breadcrumbs");
        @tags= $node[0]->find_by_tag_name("li");
        $app_info->{official_category}= $tags[4]->as_text;
        if (defined($category_mapping{$app_info->{official_category}})){
            $app_info->{trustgo_category_id}=$category_mapping{$app_info->{official_category}};
        }else{
            my $str="$market:Out of TrustGo category:".$app_info->{app_url_md5};
            $logger->error($str);
            die "Out of Category";
        }

        @node= $tree->look_down("_tag","ul","class","tab_body");
        @tags= $node[0]->find_by_tag_name("img");
        if (scalar @tags) {
            $app_info->{screenshot} = [];
            foreach (@tags){
                next if not ref $_;
                push @{$app_info->{screenshot}},$_->attr("src");
            }
        }

        if ($webpage =~ /<div class="dsp">(.*?)<\/div>/s){
            my $text =$1; 
            $text =~ s/[\000-\037]//g;
            $text =~ s/<(\/p|p|\/h3|h3|\/ul|ul|\/li|li)>/__$1__/g;
            $text =~s/<.*?>//ig;
            $text =~ s/__(.+?)__/<$1>/g;
            decode_entities( $text );
            $app_info->{description}=$text; 
        }

        @node= $tree->look_down("_tag","div","class","permission rts");
        @tags = $node[0]->find_by_tag_name("p");
        $app_info->{permission} = [];
        foreach (@tags){
            push @{$app_info->{permission}},$_->as_text;
        }

      
        @node = $tree->look_down(class=>"icon");
        $app_info->{related_app} = [] if scalar @node;
        foreach (@node) {
            next unless ref $_;
            push @{$app_info->{related_app}}, $url_base.$_->attr("href");
        }

        $app_info->{'apk_url'}="$url_base/apk/download/$1" if $app_info->{app_url}=~/(\d+)/;
        $app_info->{price}=0;

        $tree = $tree->delete;

    };
    $app_info->{status}='success';
    $app_info->{status}='fail' if $@;
    return scalar %{$app_info};
}


sub extract_page_list
{
    use File::Basename;

    my $tree;
    my @node;
    my @kids;

    my ($worker, $hook, $params, $pages) = @_;
    
    my $total_apps= 0;

    eval 
    {
        $tree = HTML::TreeBuilder->new; # empty tree
        $tree->parse($params->{'web_page'});
        
        @node = $tree->look_down( "_tag","div",class=>"tape-page" );
        @kids = $node[0]->content_list;
        $total_apps=$1 if ref $kids[0] and $kids[$#kids]->attr("href")=~ /page=(\d+)/;
        $tree = $tree->delete;
    };
    return 0 if $total_apps==0 ;

    my $index=1;
    while($index<=$total_apps){
        push( @{ $pages }, $params->{'base_url'}."&page=$index");
        ++$index;
    }
   
    return 1;
}

sub extract_app_from_feeder
{
    my $tree;
    my @node;

    my ($worker, $hook, $params, $apps) = @_;
 
    eval {

        $tree = HTML::TreeBuilder->new; # empty tree
        $tree->parse($params->{'web_page'});
        
        @node = $tree->look_down(class=>"icon");
        foreach (@node) {
            next unless ref $_;
            $apps->{$1}="$url_base".$_->attr("href") if $_->attr("href") =~ /(\d+)/;
        }
        $tree = $tree->delete;
    };

    $apps={} if $@;

    return 1;
}
