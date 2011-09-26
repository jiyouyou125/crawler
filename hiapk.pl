#!/usr/bin/perl
BEGIN{unshift(@INC, $1) if ($0=~m/(.+)\//);}
use strict;
use warnings;

use AMMS::Util;
use AMMS::AppFinder;
use AMMS::Downloader;
use AMMS::NewAppExtractor;
use AMMS::UpdatedAppExtractor;

my $task_type   = $ARGV[0];
my $task_id     = $ARGV[1];
my $conf_file   = $ARGV[2];

my $market      = 'www.hiapk.com';
my $url_base    = 'http://www.hiapk.com';
my $downloader  = new AMMS::Downloader;

my %category_mapping=(
        "\x{901A}\x{8BAF}.\x{804A}\x{5929}"=>4,
        "\x{7F51}\x{7EDC}.\x{793E}\x{533A}"=>18,
        "\x{5F71}\x{97F3}.\x{56FE}\x{50CF}"=>"7,15",
        "\x{529E}\x{516C}.\x{8D22}\x{7ECF}"=>2,
        "\x{8D44}\x{8BAF}.\x{8BCD}\x{5178}"=>"14,103",
        "\x{65C5}\x{884C}.\x{5730}\x{56FE}"=>21,
        "\x{8F93}\x{5165}\x{6CD5}.\x{7CFB}\x{7EDF}\x{5DE5}\x{5177}"=>22,
        "\x{751F}\x{6D3B}.\x{8D2D}\x{7269}"=>"17,19",
        "\x{7F8E}\x{5316}.\x{58C1}\x{7EB8}"=>12,
        "\x{9605}\x{8BFB}.\x{56FE}\x{4E66}"=>1,
        "\x{5176}\x{4ED6}"=>"-1",

        "\x{52A8}\x{4F5C}\x{5192}\x{9669}"=>800,
        "\x{89D2}\x{8272}\x{626E}\x{6F14}"=>812,
        "\x{5C04}\x{51FB}\x{98DE}\x{884C}"=>821,
        "\x{8D5B}\x{8F66}\x{7ADE}\x{901F}"=>811,
        "\x{7B56}\x{7565}\x{7ECF}\x{8425}"=>815,
        "\x{68CB}\x{724C}\x{4F11}\x{95F2}"=>803,
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
         #utf8::decode($webpage);

        $tree = HTML::TreeBuilder->new; # empty tree
        $tree->ignore_unknown(0);
        $tree->parse($webpage);
        
        @node = $tree->look_down(class=>"part_container");

        @tags= $node[0]->find_by_attribute(id=>"Apk_SoftName");
        $app_info->{app_name}=$tags[0]->as_text;
        @tags= $node[0]->find_by_attribute(id=>"Apk_SoftVersionName");
        $app_info->{current_version}=$tags[0]->as_text;

        $app_info->{official_rating_times}=0;
        @tags= $node[0]->find_by_attribute(id=>"info_m_star");

        my $app_self_id=$1 if $app_info->{app_url}=~/(\d+)\.html/;
        my $star = $downloader->download('http://sc.hiapk.com/SoftDetails.aspx?action=GetBaseInfo&callback=jsonp1313637440758&apkId='.$app_self_id);
        if( $star =~ /\$m_star m_(\d+)\$(\d+)\$/){
            $app_info->{official_rating_stars}=$1;
            $app_info->{total_install_times}=$2;
            $app_info->{official_rating_stars}=0 if( $app_info->{official_rating_stars} eq '5' );
        }elsif( $star =~ /\$m_star m_h(\d+)\$(\d+)\$/){
            $app_info->{official_rating_stars}=$1;
            $app_info->{official_rating_stars} /=10.0;
            $app_info->{total_install_times}=$2;
        }elsif( $star =~ /\$m_star \$(\d+)\$/){
            $app_info->{official_rating_stars}=5;
            $app_info->{total_install_times}=$1;
        }

        @tags= $node[0]->find_by_attribute(id=>"Apk_Download");

        @tags= $node[0]->find_by_attribute(id=>"Apk_SoftDeveloper");
        $app_info->{author}=$tags[0]->as_text;

        @tags= $node[0]->find_by_attribute(id=>"Apk_SoftSuitSdk");
        $app_info->{system_requirement} = $tags[0]->as_text;
        $app_info->{min_os_version}=$1 if $app_info->{system_requirement} =~ /([\d\.]+)/g;

        @tags= $node[0]->find_by_attribute(id=>"Apk_SoftCategory");
        $app_info->{official_category}= $tags[0]->as_text;
#use Encode;
#        Encode::_utf8_on($app_info->{official_category});
        if (defined($category_mapping{$app_info->{official_category}})){
            $app_info->{trustgo_category_id}=$category_mapping{$app_info->{official_category}};
        }else{
            my $str="$market:Out of TrustGo category:".$app_info->{app_url_md5};
            open(OUT,">>/root/outofcat.txt");
            print OUT "$str\n";
            close(OUT);
            die "Out of Category";
        }


        @tags= $node[0]->find_by_attribute(id=>"Apk_SupportScreen");
        $app_info->{resolution}=$tags[0]->as_text;

        @tags= $node[0]->find_by_attribute(id=>"Apk_SoftSize");
        my $size=$tags[0]->as_text;
        $size = $1*1024 if( $size =~ s/([\d\.]+)(.*MB)/$1/ );#MB to KB
        $size = $1  if( $size =~ s/([\d\.]+)(.*KB)/$1/ );#MB to KB
        $app_info->{size}=int($size*1024);#Bytes

        @tags=$node[0]->find_by_attribute(class=>"i_code");
        my $img_tag=$node[0]->find_by_tag_name("img");
        $app_info->{app_qr}=$img_tag->attr("src"); 
        
        @tags= $node[0]->find_by_attribute(id=>"Apk_SoftPublishTime");
        $app_info->{last_update}=$tags[0]->as_text;

        
        @tags= $node[0]->find_by_attribute(class=>"s_name"); 
        $app_info->{icon}=($tags[0]->content_list)[0]->attr("src");



        @tags=$tree->find_by_attribute(id=>"Apk_SoftImages");
        my @a_tags=$tags[0]->find_by_tag_name("a");
        if (scalar @a_tags) {
            $app_info->{screenshot} = [];
            foreach (@a_tags){
                next if not ref $_;
                push @{$app_info->{screenshot}},$_->attr("href");
            }
        }

        @node= $tree->look_down(id=>"cnt_applicationCategoryAdv");
        @a_tags=$node[0]->find_by_tag_name("a");
        $app_info->{related_app} = [] if scalar @a_tags;
        foreach(@a_tags){
            next if not ref $_;
            push @{$app_info->{related_app}},$_->attr("href");
        }

        if( $webpage =~ /<label id="Apk_Description">(.*?)<\/label>/sg)
        {
            $app_info->{description}=$1;
            $app_info->{description}=~ s/[\000-\037]//;
        }


        $app_info->{'apk_url'}= "http://sc.hiapk.com/Download.aspx?aid=$app_self_id";
        $app_info->{price}=0;


        $tree = $tree->delete;

    };
    $app_info->{status}='success';
    $app_info->{status}='fail' if $@;
    return scalar %{$app_info};
}

sub get_comment_times
{
    my $app_id= shift;

    my $url="http://www.mumayi.com/plus/comment.php?dopost=count&aid=$app_id";

    my $content = $downloader->download($url);

    return $1 if ( $downloader->is_success and $content =~ /(\d+)/ );

    return 0;
}



sub extract_page_list
{
    use File::Basename;

    my $tree;
    my @node;
    my @kids;

    my ($worker, $hook, $params, $pages) = @_;
    
    my $total_pages = 0;

    eval 
    {
        $tree = HTML::TreeBuilder->new; # empty tree
        $tree->parse($params->{'web_page'});
        
        @node = $tree->look_down(class=>"paging");
        @kids = $node[0]->find_by_tag_name("span");
        $total_pages =$kids[1]->as_text if ref $kids[1];
        $total_pages =$1 if $total_pages =~ /\/(\d+)/;
        $tree = $tree->delete;
    };
    return 0 if $total_pages==0 ;

    for (1..$total_pages) 
    {
        my $url=$params->{'base_url'};
        $url=~s/(.*)1$/$1$_/;
        push( @{ $pages }, $url);
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
        
        ##Application
        @node = $tree->look_down(id=>"Soft_AppsCategoryList");
        ##Games
        @node = $tree->look_down(id=>"Soft_GameCategoryList") unless scalar @node;
        my @li_tag = $node[0]->find_by_tag_name("li");
        foreach (@li_tag) {
            next if not ref $_;
            my @a_tag = $_->find_by_tag_name("a");
            $apps->{$1}=$a_tag[0]->attr("href") if scalar(@a_tag) && $a_tag[0]->attr("href") =~ /\/(\d+)\.html/;
        }
        $tree = $tree->delete;
    };

    $apps={} if $@;

    return 1;
}
