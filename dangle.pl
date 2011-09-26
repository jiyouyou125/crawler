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

my $market      = 'android.d.cn';
my $url_base    = 'http://android.d.cn';
my $downloader  = new AMMS::Downloader;

my %category_mapping=(
        "通讯增强"=>2209,
        "信息增强"=>2209,
        "系统工具"=>22,
        "文件管理"=>2202,
        "音乐播放"=>714,
        "图形相关"=>15,
        "网络浏览"=>2210,
        "聊天工具"=>400,
        "图书阅读"=>115,
        "学习帮助"=>5,
        "生活应用"=>19,
        "时间日程"=>1605,
        "安全保密"=>23,
        "游戏娱乐"=>6,
        "电子书籍"=>1,
        "综合软件"=>0,
        "视频播放"=>701,
        "主题美化"=>12,
        "社区交友"=>18,
        "角色扮演"=>812,
        "动作游戏"=>823,
        "冒险游戏"=>800,
        "体育运动"=>814,
        "益智休闲"=>818,
        "棋牌游戏"=>803,
        "模拟经营"=>813,
        "策略塔防"=>815,
        "养成游戏"=>807,
        "射击游戏"=>821,
        "格斗游戏"=>825,
        "飞行游戏"=>826,
        "竞速游戏"=>811,
        "其他游戏"=>8,
        "音乐游戏"=>809,
        "网络游戏"=>822,
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
        
        @node= $tree->look_down("_tag","div","class","body");
        $tag = $node[0]->find_by_tag_name("h2");
        ($app_info->{app_name},$app_info->{current_version})=$tag->as_text=~/(.*) V(.*)/i;
        @tags= $node[0]->find_by_tag_name("li");
        foreach (@tags){
            next unless ref $_;
            $app_info->{last_update}=$1 and next if $_->as_text=~/更新时间：(.*)/;
            $app_info->{author}=$1 and next if $_->as_text=~/开发商：(.*)/;
            if ($_->as_text=~/(软件|游戏|网游)类型：(.*)/){
                $app_info->{official_category}=$2;
                $app_info->{official_category}='网络游戏' if ($_->as_text=~/网游/);
                if (defined($category_mapping{$app_info->{official_category}})){
                    $app_info->{trustgo_category_id}=$category_mapping{$app_info->{official_category}};
                }else{
                    my $str="$market:Out of TrustGo category:".$app_info->{app_url_md5};
                    $logger->error($str);
                    die "Out of Category";
                }
            }
        }

        @node= $tree->look_down("_tag","div","class","picture");
        $app_info->{icon}=($node[0]->content_list)[0]->attr("src");
        $tag= $node[0]->find_by_tag_name("span");
        $app_info->{official_rating_stars}=$1 if $tag->attr("class")=~/(\d+)/;
        $app_info->{official_rating_times}=0;


        if ($webpage =~ /<div class="description">.*?<p>(.*?)<\/p>/s){
            $app_info->{description}=$1; 
            $app_info->{description}=~s/[\000-\037]+//g; 
        }
        @node= $tree->look_down("_tag","div","id","screenlist");
        @tags= $node[0]->find_by_tag_name("a");
        $app_info->{screenshot} = [] if scalar @tags;
        foreach (@tags){
            next if not ref $_;
            push @{$app_info->{screenshot}},$_->attr("href");
        }


        @node= $tree->look_down("_tag","a","class","down");
        $app_info->{'apk_url'}="$url_base".$node[0]->attr("href");

        @node=$tree->look_down("_tag","div","class","listbottom");
        @tags=$node[0]->find_by_tag_name('span');
        if ($tags[0]->as_text=~/([\.\d]+)(MB|KB)/){
            my $size = $1;
            $size = $1*1024 if( uc($2) eq "MB" );
            $app_info->{size}=int($size*1024); 
        }
        $app_info->{total_install_times}=0;
        @node=$tree->look_down("_tag","ul","class","sysversion");
        @tags=$node[0]->content_list;
        my @versions =map ( ref $_ && $_->as_text ,@tags);
        @versions = (join ',', @versions) =~ /([\d\.]+)/g;
        @versions=sort @versions;
        $app_info->{min_os_version}=$versions[0];
        $app_info->{max_os_version}=$versions[$#versions];

        @node=$tree->look_down("_tag","div","class","permdesc");
        @tags=$node[0]->find_by_tag_name("li");
        $app_info->{permission} = [] if scalar @tags;
        foreach (@tags){
            push @{$app_info->{permission}},$1 if $_->as_text=~/- (.*)/;
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

    push( @{ $pages }, $params->{'base_url'});
    eval 
    {
        $tree = HTML::TreeBuilder->new; # empty tree
        $tree->parse($params->{'web_page'});
        
        @node = $tree->look_down( "_tag","div",class=>"pager" );
        @kids = $node[0]->find_by_tag_name("a");

        my @page_index=map ($_->attr("href"), @kids);
        @page_index = (join ',', @page_index) =~ /-(\d+)/g;
        @page_index=keys %{{ map { $_ => 1 } @page_index }};
        @page_index=sort {$a <=> $b} @page_index;


        $total_pages=$page_index[$#page_index] if (scalar @page_index)>0;
        $tree = $tree->delete;
    };
    return 0 if $total_pages==0 ;

    my $index=2;
    while($index<=$total_pages ){
        my $url= $params->{'base_url'};
        $url=~s/\/$//g;
        if($url =~/netgame/){
            push( @{ $pages }, $url."-$index?k=");
        }else{
            push( @{ $pages }, $url."-$index?r=&k=");
        }
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
        
        @node = $tree->look_down("_tag","div","class","gamelist");
        unless (scalar @node){
            @node = $tree->look_down("_tag","div","class","netgamelist");
        }
        my @tags=$node[0]->find_by_tag_name("a");
        foreach (@tags) {
            next unless ref $_;
            $apps->{$1}="$url_base".$_->attr("href") if $_->attr("href") =~ /(\d+)/;
        }
        $tree = $tree->delete;
    };

    $apps={} if $@;

    return 1;
}
