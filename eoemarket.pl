#!/usr/bin/perl
BEGIN{unshift(@INC, $1) if ($0=~m/(.+)\//);}
use strict;
use warnings;

use Digest::MD5 qw(md5_hex);
use HTML::Entities;
use AMMS::Util;
use AMMS::AppFinder;
use AMMS::Downloader;
use AMMS::NewAppExtractor;
use AMMS::UpdatedAppExtractor;

my $task_type   = $ARGV[0];
my $task_id     = $ARGV[1];
my $conf_file   = $ARGV[2];

my $market      = 'www.eoemarket.com';
my $url_base    = 'http://www.eoemarket.com';
my $downloader  = new AMMS::Downloader;

my %category_mapping=(
        "\x{7CFB}\x{7EDF}\x{5DE5}\x{5177}"=>22,
        "\x{751F}\x{6D3B}\x{5A31}\x{4E50}"=>"19,6",
        "\x{793E}\x{533A}\x{4EA4}\x{53CB}"=>18,
        "\x{7F51}\x{7EDC}\x{901A}\x{4FE1}"=>4,
        "\x{5C0F}\x{8BF4}\x{6F2B}\x{753B}"=>"1,3",
        "\x{94C3}\x{58F0}\x{89C6}\x{9891}"=>7,
        "\x{684C}\x{9762}\x{7F8E}\x{5316}"=>12,
        "\x{5546}\x{52A1}\x{8D22}\x{7ECF}"=>2,
        "\x{98DE}\x{884C}\x{5C04}\x{51FB}"=>821,
        "\x{52A8}\x{4F5C}\x{5192}\x{9669}"=>800,
        "\x{76CA}\x{667A}\x{4F11}\x{95F2}"=>818,
        "\x{89D2}\x{8272}\x{626E}\x{6F14}"=>812,
        "\x{68CB}\x{724C}\x{5929}\x{5730}"=>803,
        "\x{7ECF}\x{8425}\x{7B56}\x{7565}"=>815,
        "\x{4F53}\x{80B2}\x{7ADE}\x{6280}"=>814,
        "\x{7F51}\x{7EDC}\x{6E38}\x{620F}"=>822,
    );
die "\nplease check config parameter\n" unless init_gloabl_variable( $conf_file );
my $dbh         = $db_helper->get_db_handle;

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
        
        @node= $tree->look_down("_tag","div","class","hot_r ");
        @tags= $node[0]->find_by_tag_name("a");
        $app_info->{official_category}= $tags[2]->as_text;
        if (defined($category_mapping{$app_info->{official_category}})){
            $app_info->{trustgo_category_id}=$category_mapping{$app_info->{official_category}};
        }else{
            my $str="$market:Out of TrustGo category:".$app_info->{app_url_md5};
            $logger->error($str);
            die "Out of Category";
        }

        @node= $tree->look_down("_tag","div","class","md_top");
        @tags= $node[0]->look_down("_tag","img","class","icon");
        $app_info->{icon}=$tags[0]->attr("src");
        $app_info->{app_name}=$tags[0]->attr("alt");
        my @dl_tags=$node[0]->find_by_tag_name("dl");
        my $tag=$dl_tags[0]->find_by_tag_name("span");
        $app_info->{current_version}=$1 if $tag->as_text=~/([\d\.]+)/;
        $tag=$dl_tags[0]->find_by_tag_name("i");
        $app_info->{official_rating_stars}= $tag->attr("title");
        $app_info->{official_rating_times}=0;
        @tags=$dl_tags[0]->find_by_attribute(class=>"size");
        if( $tags[0]->as_text=~/([\d\.]+\s*)(MB|KB).*(\d+)/){
            my $size = $1;
            $size = $1*1024 if( uc($2) eq "MB" );
            $app_info->{size}=int($size*1024); 
            $app_info->{total_install_times}=$3;
        }
        $app_info->{min_os_version}=$1 if( $tags[1]->as_text=~/([\d\.]+)/);

        $app_info->{price}=0;

        
        @tags= $node[0]->look_down("class","down_1");
        $tag=$tags[0]->find_by_tag_name("a");
        $app_info->{'apk_url'}=decode_entities($tag->attr("href")) if ref $tag;

        if ($webpage =~ /<div class="d_details">(.*?)<\/div>/s){
            my $text =$1; 
            $text =~ s/[\000-\037]//g;
            decode_entities( $text );
            $app_info->{description}=$text; 
        }


        $app_info->{author}="\x{672A}\x{77E5}";
        @node= $tree->look_down("class","time");
        my $hash_ref=$dbh->selectrow_hashref("select last_update from app_extra_info where app_url_md5='$app_info->{app_url_md5}'");
        $app_info->{last_update}=substr $hash_ref->{'last_update'},0,10;

        @node= $tree->look_down("_tag","img","class","screenshot");
        $app_info->{screenshot} = [];
        foreach (@node){
            next if not ref $_;
            push @{$app_info->{screenshot}},$_->attr("src");
        }

        @node = $tree->look_down("_tag","div","class","taday_con");
        @tags = $node[0]->look_down("_tag","a","class","appname");
        $app_info->{related_app} = [] if scalar @tags;
        foreach (@tags) {
            next unless ref $_;
            push @{$app_info->{related_app}}, $url_base.$_->attr("href");
        }

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
    
    my $total_pages= 0;

    eval 
    {
        $tree = HTML::TreeBuilder->new; # empty tree
        $tree->parse($params->{'web_page'});
        
        @node = $tree->look_down( "_tag","div",class=>"pagination" );
        @kids = $node[0]->find_by_tag_name("a");

        my @page_index=map ($_->as_text, @kids);
        @page_index=grep /\d+/, @page_index;
        @page_index=sort {$a <=> $b} @page_index;

        $total_pages=$page_index[$#page_index];
        $tree = $tree->delete;
    };
    return 0 if $total_pages==0 ;

    my $index=1;
    while($index<=$total_pages ){
        push( @{ $pages }, $params->{'base_url'}."/order/down/page/$index");
        ++$index;
    }
   
    return 1;
}

sub extract_app_from_feeder
{
    my $tree;
    my @node;
    my @tags;

    my ($worker, $hook, $params, $apps) = @_;
 
    my $sql="replace into app_extra_info set app_url_md5=?,last_update=?";
    my $sth=$dbh->prepare($sql);
    eval {
        $tree = HTML::TreeBuilder->new; # empty tree
        $tree->parse($params->{'web_page'});
        
        @node = $tree->look_down("_tag","div", "class","appcell");
        foreach (@node) {
            next unless ref $_;
            @tags = $_->look_down("_tag","div", "class","tit");
            my $a_tag=$tags[0]->find_by_tag_name("a");
            $apps->{$1}="$url_base".$a_tag->attr("href") if $a_tag->attr("href") =~ /(\d+)/;
            my $md5=md5_hex("$url_base".$a_tag->attr("href") );

            ##insert last update because it can't be got in detail
            if( $_->as_text=~/\x{53D1}\x{5E03}\x{65E5}\x{671F}\x{FF1A}(\d+-\d+-\d{1,2})/){
                $sth->execute($md5,$1);
            }
        }
        $tree = $tree->delete;
    };

    $apps={} if $@;

    return 1;
}
