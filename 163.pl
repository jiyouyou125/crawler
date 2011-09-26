#!/usr/bin/perl
BEGIN{unshift(@INC, $1) if ($0=~m/(.+)\//);}
use strict;
use warnings;

use utf8;
use POSIX;
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

my $market      = 'm.163.com';
my $url_base    = 'http://m.163.com';
my $downloader  = new AMMS::Downloader;

my %category_mapping=(
        "工具"=>22,
        "游戏"=>8,
        "社交"=>18,
        "娱乐"=>6,
        "摄影"=>15,
        "影音"=>7,
        "阅读"=>1,
        "生活"=>19,
        "新闻"=>14,
        "办公"=>16,
        "教育"=>5,
        "导航"=>13,
        "系统"=>12,
        "安全"=>23,
        "浏览器"=>2210,
        "输入法"=>2217,
        "健康"=>9,
        "旅游"=>21,
        "购物"=>17,
        "理财"=>2,
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
        
        @node= $tree->look_down("_tag","div","class","box-ed-main-content");
        $tag= $node[0]->look_down("class","arti-ed-title");
        $app_info->{app_name}=$tag->as_text;
        $app_info->{official_rating_times}=$1 if $node[0]->as_text=~/综合评分：\((\d+)/;
        $app_info->{official_rating_stars}=$1/2.0 if $node[0]->as_text=~/人\)([\d\.]+)/;
        $app_info->{price}=0;
        if( $node[0]->as_text=~/类别：(.+?)版本：(.+?)系统要求：(.+?)软件大小：(.+?)开发者：(.+?)打分/)
        {
            my $version=$3;
            my $size=$4;
            $app_info->{official_category}=$1;
            $app_info->{current_version}=$2;
            $app_info->{author}=$5;
            $app_info->{min_os_version}=$1 if $version=~/([\d\.]+)/;
            if ($size=~/([\d\.]+)(M|K)/){
                $size=$1;
                $size = $1*1024 if( uc($2) eq "M" ) 
            }
            $app_info->{size}=int($size*1024); 
        }
        
        $tag = $node[0]->look_down("id","app-download-1");
        $app_info->{'apk_url'}=$tag->attr("href") if ref $tag;
        decode_entities($app_info->{'apk_url'});

        $tag= $tree->look_down("_tag","img","id","pic");
        $app_info->{icon}=$tag->attr("src");
        if ($webpage =~ /id="app-desc".*?>(.*?)<\/div>/s){
            $app_info->{description}=$1; 
            $app_info->{description}=~s/[\000-\037]+//g; 
            decode_entities($app_info->{'description'});
        }

        my $hash_ref=$dbh->selectrow_hashref("select last_update from app_extra_info where app_url_md5='$app_info->{app_url_md5}'");
        $app_info->{last_update}=substr $hash_ref->{'last_update'},0,10;

        if (defined($category_mapping{$app_info->{official_category}})){
            $app_info->{trustgo_category_id}=$category_mapping{$app_info->{official_category}};
        }else{
            my $str="$market:Out of TrustGo category:".$app_info->{app_url_md5};
            $logger->error($str);
#die "Out of Category";
        }

        my $app_self_id=$1 if $app_info->{app_url}=~ /([^\/]+)\.html$/;
        my $url="http://m.163.com/ajax/softinfo/img_$app_self_id.json";
        my $content=$downloader->download($url);
        return "can't downloand screenshot" unless $downloader->is_success;
        my @links=$content=~/("http.*?")/gs;
        @links=keys %{{ map { $_ => 1 } @links}};
        $app_info->{screenshot} = \@links if scalar @links;

        @node= $tree->look_down("_tag","li","class","li-rank");
        $app_info->{related_app} = [] if scalar @node;
        foreach(@node){
            next unless ref $_;
            $tag=$_->find_by_tag_name("a");
            push @{$app_info->{related_app}},"$url_base".$tag->attr("href");
        }


        $tree = $tree->delete;

    };
    $app_info->{status}='success';
    $app_info->{status}='fail' if $@;
    return scalar %{$app_info};
}


sub extract_page_list
{
    my ($worker, $hook, $params, $pages) = @_;
    
    my $total_pages= 0;
    my $total_apps = 0;

    eval 
    {
        my $category=$1 if $params->{'base_url'}=~/([^\/]+)\.html$/;
        $category=uc($category);
        my $url="http://m.163.com/ajax/category/$category/start_0-display_detail-sort_download-asc_0.js";
        my $content=$downloader->download($url);
        return 0 unless $downloader->is_success;
        $total_apps=$1 if $content=~/\{"count":(\d+)/;
        $total_pages= ceil($total_apps/20);
    };
    warn "no page for $params->{'base_url'}" and return 0 if $total_apps==0 ;

    my $index=1;
    while($index<=$total_pages){
        push( @{ $pages }, $params->{base_url}."#appsview=start_".(($index-1)*20)."-display_detail-sort_download-asc_0");
        ++$index;
    }
   
    return 1;
}

sub extract_app_from_feeder
{
    my ($worker, $hook, $params, $apps) = @_;
 
    eval {

        my $category;
        my $start_num;
        if ($params->{'base_url'}=~/category\/(.*?)\.html.*start_(\d+)/){
            $category=$1; 
            $start_num=$2; 
        }else{
            warn "Format error for $params->{'base_url'}";
        }
        $category=uc($category);
        my $url="http://m.163.com/ajax/category/$category/start_$start_num-display_detail-sort_download-asc_0.js";
        my $content=$downloader->download($url);
        return 0 unless $downloader->is_success;
        my @links = $content=~/"link":"(.*?)",/g;
        my @updateTime= $content=~/"updateTime":(.*?),/g;
    
        $logger->error("number is not consistent for $params->{'base_url'}") and return 0 if scalar @links != scalar @updateTime;
        my $sql="replace into app_extra_info set app_url_md5=?,last_update=?";
        my $sth=$dbh->prepare($sql);

        my $md5;
        my $index=0;
        foreach (@links) {
            next unless defined $_;
            $apps->{$1}="$url_base$_" if $_=~ /([^\/]+)\.html$/;
            $md5=md5_hex($apps->{$1});
            my $date=substr $updateTime[$index],0,10;
            $sth->execute($md5,strftime "%Y-%m-%d %H:%M:%S", localtime($date));
            ++$index;
        }
    };

    $apps={} if $@;

    return 1;
}
