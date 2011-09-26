#!/usr/bin/perl
BEGIN{unshift(@INC, $1) if ($0=~m/(.+)\//);}
use strict;
use warnings;

use utf8;
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

my $market      = 'www.goapk.com';
my $url_base    = 'http://www.goapk.com';
my $downloader  = new AMMS::Downloader;

my %category_mapping=(
        "实用工具"=>16,
        "系统工具"=>22,
        "社交通信"=>"18,4",
        "旅行天气"=>21,
        "影音漫画"=>"7,3",
        "商务财经"=>2,
        "生活助手"=>19,
        "阅读资讯"=>14,
        "美化壁纸"=>12,
        "学习人文"=>5,
        "网络连接"=>2216,
        "电子书"=>1,
        "其他"=>0,
        "创意休闲"=>818,
        "动作射击"=>821,
        "益智棋牌"=>803,
        "角色扮演"=>812,
        "体育竞速"=>811,
        "网络游戏"=>822,
        "模拟游戏"=>813,
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
    my $tag;
    my @node;
    my @tags;
    my ($worker, $hook, $webpage, $app_info) = @_;

    eval {
#utf8::encode($webpage);

        $tree = HTML::TreeBuilder->new; # empty tree
        $tree->ignore_unknown(0);
        $tree->parse($webpage);
        
        @node= $tree->look_down("_tag","div","class","l img");
        $app_info->{icon}=($node[0]->content_list)[0]->attr("src");

        @node= $tree->look_down("_tag","div","class","l con");
        my $text=$node[0]->as_text;
        $app_info->{current_version}=$1 if $webpage=~/class="l con">.*?<\/a>.*?([\d\.]+).*?<img/s;

        @tags= $node[0]->find_by_tag_name("img");
        $app_info->{official_rating_stars}=$1/2.0 if $tags[0]->attr("src")=~/(\d+)/;
        $app_info->{official_rating_times}=0;



        @tags= $node[0]->find_by_tag_name("a");
        $app_info->{app_name}=$tags[0]->as_text;
        @tags= $node[0]->find_by_tag_name("span");
        $app_info->{author}="\x{672A}\x{77E5}";
        $text=$tags[0]->as_text;
        $text=~s/..$//g;
        $app_info->{author}=$1 if $text=~/:(.+)/g;
        $app_info->{author}="\x{672A}\x{77E5}" if $app_info->{author}!~/\w/g;
        $app_info->{last_update}=$1 if $tags[1]->as_text=~/([-\d]+)/g;
        if ($tags[2]->as_text=~/([\.\d]+)(MB|KB)/){
            my $size = $1;
            $size = $1*1024 if( uc($2) eq "MB" );
            $app_info->{size}=int($size*1024); 
        }
        $app_info->{total_install_times}=$1 if $tags[3]->as_text=~/(\d+)/g;

        @node= $tree->look_down("_tag","div","class","l install");
        @tags= $node[0]->find_by_tag_name("a");
        $app_info->{'apk_url'}="$url_base".$tags[0]->attr("href");
        if ($webpage =~ /<div id="fz".*?>(.*?)<\/div>/s){
            $app_info->{description}=$1; 
            $app_info->{description}=~s/[\000-\037]+//g; 
        }

        @node= $tree->look_down("_tag","DIV","id","ISL_Cont_1");
        @tags= $node[0]->find_by_tag_name("IMg");
        $app_info->{screenshot} = [] if scalar @tags;
        foreach (@tags){
            next if not ref $_;
            push @{$app_info->{screenshot}},$_->attr("src");
        }

        @node = $tree->look_down("_tag","div","class","content");
        @tags = $node[0]->look_down("_tag","div","class","img");
        $app_info->{related_app} = [] if scalar @tags;
        foreach (@tags) {
            next unless ref $_;
            $tag= $node[0]->find_by_tag_name("a");
            push @{$app_info->{related_app}}, $url_base.$tag->attr("href");
        }

        @node = $tree->look_down("_tag","meta","name","keywords");
        my $category = $node[0]->attr("content");
        $app_info->{official_category}= (split ',', $category)[2];
        if (defined($category_mapping{$app_info->{official_category}})){
            $app_info->{trustgo_category_id}=$category_mapping{$app_info->{official_category}};
        }else{
            my $str="$market:Out of TrustGo category:".$app_info->{app_url_md5};
            $logger->error($str);
            die "Out of Category";
        }


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
    
    my $total_pages= 0;

    eval 
    {
        $tree = HTML::TreeBuilder->new; # empty tree
        $tree->parse($params->{'web_page'});
        
        @node = $tree->look_down( "_tag","div",id=>"fenye" );
        @kids = $node[0]->find_by_tag_name("a");

        my @page_index=map ($_->attr("href"), @kids);
        @page_index = (join ',', @page_index) =~ /p=(\d+)/g;
        @page_index=sort {$a <=> $b} @page_index;

        $total_pages=$page_index[$#page_index];
        $tree = $tree->delete;
    };
    return 0 if $total_pages==0 ;

    my $index=1;
    while($index<=$total_pages ){
        push( @{ $pages }, $params->{'base_url'}."&p=$index");
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
 
    eval {
        $tree = HTML::TreeBuilder->new; # empty tree
        $tree->parse($params->{'web_page'});
        
        @node = $tree->look_down("_tag","table");
        foreach (@node) {
            next unless ref $_;
            my $a_tag=$_->find_by_tag_name("A");
            $apps->{$1}="$url_base".$a_tag->attr("href") if $a_tag->attr("href") =~ /=(\d+)/;
        }
        $tree = $tree->delete;
    };

    $apps={} if $@;

    return 1;
}
