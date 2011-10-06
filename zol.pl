#!/usr/bin/perl
BEGIN { unshift( @INC, $1 ) if ( $0 =~ m/(.+)\// ); }
use strict;
use utf8;
use warnings;
use File::Basename;
use Digest::MD5 qw/md5_hex/;
use HTML::TreeBuilder;
use Encode;

use AMMS::Util;
use AMMS::AppFinder;
use AMMS::Downloader;
use AMMS::NewAppExtractor;
use AMMS::UpdatedAppExtractor;
use AMMS::DBHelper;
use Data::Dumper;

#require "zol_action.pl";

my $task_type = $ARGV[0];
my $task_id   = $ARGV[1];
my $conf_file = $ARGV[2];

my $market   = "sj.zol.com.cn";
my $url_base = "http://sj.zol.com.cn";

my $downloader = new AMMS::Downloader;

my %category_mapping = (
    "同步软件"    => 222,
    "辅助软件"    => 1,
    "系统管理"    => 1,
    "中文输入"    => 2217,
    "红外蓝牙"    => 22,
    "同步备份"    => 2200,
    "文件管理"    => 2202,
    "固件补丁"    => 22,
    "固件驱动"    => 22,
    "影音播放"    => 7,
    "影音媒体"    => 7,
    "网络相关"    => "4,18",
    "安全助手"    => 23,
    "导航地图"    => "13,21",
    "应用工具"    => 22,
    "桌面插件"    => 22,
    "读书教育"    => "1,5",
    "游戏娱乐"    => "6,8",
    "即时聊天"    => 400,
    "即时通信"    => 400,
    "通信辅助"    => 22,
    "动作游戏"    => 823,
    "策略战棋"    => 815,
    "影像工具"    => 7,
    "商务办公"    => "2,16",
    "益智休闲"    => "808,818",
    "射击游戏"    => 821,
    "格斗游戏"    => 825,
    "体育运动"    => 20,
    "角色扮演"    => 812,
    "主题壁纸"    => 12,
    "主题插件"    => 12,
    "中文输入法" => 2217,
    "新闻资讯"    => 14,
    "解谜冒险"    => 800,
    "塔防游戏"    => 8,
    "音乐游戏"    => 809,
    "其它游戏"    => 8,
    "飞行游戏"    => 826,
    "Rom及补丁"    => 22,
    "金融理财"    => 2,
    "影音播放器" => 7,
    "生活助手"   => 16,
);

die "\nplease check config parameter\n" unless init_gloabl_variable($conf_file);

if ( $task_type eq 'find_app' )    ##find new android app
{
    my $AppFinder =
      new AMMS::AppFinder( 'MARKET' => $market, 'TASK_TYPE' => $task_type );
    $AppFinder->addHook( 'extract_page_list',       \&extract_page_list );
    $AppFinder->addHook( 'extract_app_from_feeder', \&extract_app_from_feeder );
    $AppFinder->run($task_id);
}
elsif ( $task_type eq 'new_app' )    ##download new app info and apk
{
    my $NewAppExtractor = new AMMS::NewAppExtractor(
        'MARKET'    => $market,
        'TASK_TYPE' => $task_type
    );
    $NewAppExtractor->addHook( 'extract_app_info', \&extract_app_info );
    $NewAppExtractor->run($task_id);
}
elsif ( $task_type eq 'update_app' )    ##download updated app info and apk
{
    my $UpdatedAppExtractor = new AMMS::UpdatedAppExtractor(
        'MARKET'    => $market,
        'TASK_TYPE' => $task_type
    );
    $UpdatedAppExtractor->addHook( 'extract_app_info', \&extract_app_info );
    $UpdatedAppExtractor->run($task_id);
}

exit;

sub extract_app_info {
    my $tree;
    my @node;
    my @tags;
    my @kids;
    my ( $worker, $hook, $webpage, $app_info ) = @_;

    eval {
        $tree = HTML::TreeBuilder->new;
        $webpage = decode( "gb2312", $webpage );
        $tree->parse($webpage);

        #official category
        my $category_page_url = $tree->look_down(class => "page_url");
        my @category_a = $category_page_url->find_by_tag_name("a");
        $app_info->{official_category} = trim($category_a[1]->as_text) if ref $category_a[1];

        #trustgo_category_id
        if ( defined( $category_mapping{ $app_info->{official_category} } ) ) {
            $app_info->{trustgo_category_id} =
              $category_mapping{ $app_info->{official_category} };
        }
        else {
            my $str = "Out of TrustGo category:" . $app_info->{app_url_md5};
            open( OUT, ">>/home/nightlord/outofcat.txt" );
            print OUT "$str\n";
            close(OUT);
            die "Out of Category";
        }

     #last_update app_name current_version total_install_times get from database
        my $dbh = new AMMS::DBHelper;
        my $app_extra_info =
          $dbh->get_extra_info( md5_hex( $app_info->{app_url} ) );
        if ( ref $app_extra_info eq "HASH" ) {
            $app_info->{last_update}     = $app_extra_info->{last_update};
            $app_info->{app_name}        = $app_extra_info->{app_name};
            $app_info->{current_version} = $app_extra_info->{current_version};
            $app_info->{total_install_times} =
              $app_extra_info->{total_install_times};
            $app_info->{size} = $app_extra_info->{size};
        }

        #app_price
        $app_info->{price} = 0;

        #descripton
        my $node = $tree->look_down( id => "info_more" );
        if ($node) {
            my $description_info = $node->as_text;
            $description_info =~ s/\[.收起全部简介\]//;
            $app_info->{description} = $description_info;
        }
        if ( not defined($node) ) {
            my @main_class = $tree->look_down( class => "main" );
            $app_info->{description} = $main_class[2]->as_text
              if ref $main_class[2];
        }

        #icon
        my $main_class_first = $tree->look_down( class => "main" );
        my $icon_img = $main_class_first->find_by_tag_name("img");
        $app_info->{icon} = $icon_img->attr("src");

        #apk_url
        if ( $webpage =~ /电信下载.*?'(\/down\.php.*?)'.*?/s ) {
            $app_info->{apk_url} = $url_base . $1 . "0";
        }

        #screens
        my $screen_pre = $main_class_first->find_by_tag_name("a");
        my $downloader = new AMMS::Downloader;
        my $res =
          $downloader->download( $url_base . $screen_pre->attr("href") );
        my $screenshot_num;
        if ( $webpage =~ /软件截图.*?\((\d+)\)/s ) {
            $screenshot_num = $1;
        }
        if ( $res && $screenshot_num ne "0" ) {
            my @screens;
            my $content = $res;
            $content = decode( "gb2312", $content );
            my $tree_s = HTML::TreeBuilder->new;
            $tree_s->parse($content);
            my $main = $tree_s->look_down( class => "main" );
            my @img_tags = $main->look_down( "_tag", "img" );
            foreach my $img (@img_tags) {
                my $img_src = $img->attr("src");
                $img_src =~ s/\/\d+x\d+//;
                push @screens, $img_src;
            }
            $app_info->{screenshot} = \@screens;
            $tree_s->delete;
        }
        $tree->delete;
    };
    $app_info->{status} = 'success';
    $app_info->{status} = 'fail' if $@;
    return scalar %{$app_info};
}

sub extract_page_list {

    my ( $worker, $hook, $params, $pages ) = @_;

    my $webpage = $params->{'web_page'};
    $webpage = decode( "gb2312", $webpage );
    my $total_pages = 0;
    eval {
        my $per_page;
        if ( $webpage =~ /每页(\d+)款.*?共(\d+)页/s ) {
            $per_page    = $1;
            $total_pages = $2;
        }
        if ( $total_pages eq "1" ) {
            $pages = $1 if $params->{base_url} =~ /sub(\d+)/;
        }
        else {
            if ( $webpage =~ /page3.*?href="(.*?)"/ ) {
                my $page_tmp = $1;
                my $page_base = $1 if $page_tmp =~ /(.*?_)\d+\.html/;
                for ( 1 .. $total_pages ) {
                    push @{$pages}, $url_base . "" . $page_base . $_ . ".html";
                }
            }
        }
    };
    return 0 if $total_pages == 0;

    return 1;
}

sub extract_app_from_feeder {
    my $tree;
    my @node;

    my ( $worker, $hook, $params, $apps ) = @_;

    eval {
        my $webpage = $params->{'web_page'};

        $webpage = decode( "gb2312", $webpage );
        $tree = HTML::TreeBuilder->new;
        my $dbh = new AMMS::DBHelper;
        $tree->no_expand_entities(1);
        $tree->parse($webpage);
        my @nodes = $tree->look_down(
            "_tag", "dl",
            sub {
                defined( $_[0]->attr("id") ) && $_[0]->attr("id") =~ /^module/;
            }
        );
        for my $node (@nodes) {

            #app_url
            my $a_tag   = $node->find_by_tag_name("a");
            my $app_url = $url_base . "" . $a_tag->attr("href");
            $apps->{$1} = $app_url
              if basename( $a_tag->attr("href") ) =~ /(\d+)/;
            my $dd_tag    = $node->find_by_tag_name("dd");
            my @span_tag  = $dd_tag->find_by_tag_name("span");
            my $name_info = $dd_tag->find_by_tag_name("a")->as_text;
            my ( $app_name, $app_version ) =
              ( $name_info =~ /(.*?)[vV]?([\d\.]+).*/ );

            if ( scalar @span_tag ) {

                #last_update
                $dbh->save_extra_info(
                    md5_hex($app_url),
                    {
                        last_update         => $span_tag[1]->as_text,
                        size                => kb_m( $span_tag[0]->as_text ),
                        total_install_times => $span_tag[2]->as_text,
                        app_name            => $app_name,
                        current_version     => $app_version,
                    }
                );
            }
        }
    };

    $apps = {} if $@;

    return 1;
}

sub kb_m {
    my $size = shift;

    # MB -> KB
    $size = $1 * 1024 if ( $size =~ s/([\d\.]+)(.*MB.*)/$1/i );
    $size = $1        if ( $size =~ s/([\d\.]+)(.*KB.*)/$1/i );

    # return byte
    return int( $size * 1024 );
}

