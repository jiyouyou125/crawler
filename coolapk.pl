#!/usr/bin/perl 
#===============================================================================
#
#         FILE: coolapk
#        USAGE: task_type task_id configure
# for example => $0 find_app 144 ./default.cfg
#  DESCRIPTION: 
#      This is a program,which is a adaptor for the crawler of amms system,
# it can parse html meta data and support extract_page_list,extract_app_from_feeder,
# extract_app_info.Somewhere used HTML::TreeBuilder to parse html tree, handle 
# description,stars... with regular expression.
#
# REQUIREMENTS: HTML::TreeBuilder,AMMS::UpdatedAppExtractor,AMMS::Downloader,
#               AMMS::NewAppExtractor,AMMS::AppFinder,AMMS::Util
#         BUGS: send email to me, if there is any bugs.
#        NOTES: 
#       AUTHOR: James King, jinyiming456@gmail.com
#      VERSION: 1.0
#      CREATED: 2011/9/24 13:35
#     REVISION: 1.0
#===============================================================================

use strict;
use warnings;

BEGIN{
    unshift(@INC, $1) if ($0=~m/(.+)\//);
}
use strict;
use utf8;
use warnings;
use HTML::TreeBuilder;
use Carp ;
use File::Path;
use URI::URL;
use IO::File;
use English;
use Encode qw( encode );
use File::Path;
use Digest::MD5 qw(md5_hex);

use HTTP::Status;
use HTTP::Date;
use HTTP::Request;
use HTTP::Cookies;
use LWP::UserAgent;
use LWP::Simple;

# use AMMS Module
use AMMS::Util;
use AMMS::AppFinder;
use AMMS::Downloader;
use AMMS::NewAppExtractor;
use AMMS::UpdatedAppExtractor;

# Export function for test
require Exporter;
our @ISA     = qw(Exporter);
our @EXPORT_OK  = qw(
    extract_page_list 
    extract_app_from_feeder 
    extract_app_info
);

my $task_type   = $ARGV[0];
my $task_id     = $ARGV[1];
my $conf_file   = $ARGV[2];

my $market      = 'www.coolapk.com';
my $url_base    = 'http://www.coolapk.com';
#my $downloader  = new AMMS::Downloader;

my $login_url = 'http://www.coolapk.com/do.php?ac=login';
my $cookie_file = "/root/crawler/cookie.coolapk";
#my $cookie_file = "f:/crawler/cookie.coolapk";
# for permission ajax fetch content
my $permission_url
	= 'http://www.coolapk.com/do.php?ac=ajax&inajax=1&op=viewpermissions&d=1316753629742';

my $usage =<<EOF;
==================================================
$0 task_type task_id conf_file
for example:
    $0 find_app     10 /root/crawler/default.cfg
    $0 new_app      158 /root/crawler/default.cfg
    $0 update_app   168 /root/crawler/default.cfg
--------------------------------------------------
explain:
    task_type   - task type which like as 'find_app' 'new_app' 'update_app'
    task_id     - task_id number,you can get it from task_detail table
    conf_file   - the configure file of crawler,default is /root/crawler/default.cfg
==================================================
EOF

# check args 
unless( $task_type && $task_id && $conf_file ){
    die $usage;
}

# check configure
die "\nplease check config parameter\n" 
    unless init_gloabl_variable( $conf_file );

our %category_mapping=(
    "系统工具"    => 22,
    "主题美化"    => 1203,
    "社交聊天"    => "18,400",
    "网络工具"    => "2210,2206",
    "媒体娱乐"    => 7,
    "桌面插件"    => 1206,
    "资讯阅读"    => 1,
    "出行购物"    => "17,21",
    "生活助手"    => 19,
    "实用工具"    => 9,
    "财经投资"    => 2,

    "其他"        => 0,

    # 游戏
    "休闲游戏"    => 818,
    "益智游戏"    => 810,
    "棋牌游戏"    => 802,
    "体育运动"    => 814,
    "动作射击"    => 821,
);

# define a app_info mapping
# because trustgo_category_id is related with official_category
# so i remove it from this mapping
our %app_map_func = (
        author                  => \&get_author, 
        app_name                => \&get_app_name,
        current_version         => \&get_current_version,
        icon                    => \&get_icon,
        price                   => \&get_price,
        system_requirement      => \&get_system_requirement,
        min_os_version          => \&get_min_os_version,
        max_os_version          => \&get_max_os_version,
        resolution              => '',
        last_update             => \&get_last_update,
        size                    => \&get_size,
        official_rating_stars   => \&get_official_rating_stars,
        official_rating_times   => \&get_official_rating_times,
        app_qr                  => \&get_app_qr,
        note                    => '',
        apk_url                 => \&get_apk_url, 
        total_install_times     => \&get_total_install_times,
        description             => \&get_description,
        official_category       => \&get_official_category,
        trustgo_category_id     => '',
        related_app             => \&get_related_app,
        screenshot               => \&get_screenshot,
        permission              => \&get_permission,
        status                  => '',
        category_id             => '',
);

our @app_info_list = qw(
        author                  
        app_name
        current_version
        icon                    
        price                   
        system_requirement      
        min_os_version          
        max_os_version          
        resolution              
        last_update             
        size                    
        official_rating_stars   
        official_rating_times   
        app_qr                  
        apk_url                 
        total_install_times     
        description             
        official_category       
        trustgo_category_id     
        related_app             
        screenshot               
        permission              
        status                  
);

our $AUTHOR     = '酷安网';

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
    $NewAppExtractor->addHook('download_app_apk',\&download_app_apk);
    $NewAppExtractor->run($task_id);
}
elsif( $task_type eq 'update_app' )##download updated app info and apk
{
    my $UpdatedAppExtractor= new AMMS::UpdatedAppExtractor('MARKET'=>$market,'TASK_TYPE'=>$task_type);
    $UpdatedAppExtractor->addHook('extract_app_info', \&extract_app_info);
    $UpdatedAppExtractor->addHook('download_app_apk',\&download_app_apk);
    $UpdatedAppExtractor->run($task_id);
}

sub get_page_list{
    my $html        = shift;
    my $page_mark   = shift;
    my $pages       = shift;

    my $tree = new HTML::TreeBuilder;
    $tree->parse($html);
    # <a href="/apk/downloads/list-56/?p=56&sort=lastdown">最末页</a>

    my @nodes = $tree->look_down( id => 'pagelist' );
    Carp::croak('not find page_make : pagelist ') unless scalar(@nodes);

    my @tags = $nodes[0]->find_by_tag_name('a');
    return unless @tags;
    # /apk/news/list-4/?p=4&sort=default
    my $last_page = $tags[-1]->attr('href');
    if( $last_page =~ m/###/ ){
        $last_page = 1;
        my @page = $nodes[0]->look_down( class => 'selc');
        push @{$pages},  $url_base.$page[0]->attr('href');
        return
    }

    ( my $needed_s_url = $last_page ) =~ s/list-(\d+)/'list-'.'$num'/e;
    my $total = $1;
    $needed_s_url =~ s/p=\d+/'p='.'$num'/e;

    # save pages to pages arrayref
    @{ $pages } = map {
        ( my $temp = $needed_s_url ) =~ s/\$num/$_/g; 
        trim_url($url_base).$temp;
    } (1..$total);
    $tree->delete;
}


sub trim_url{
    my $url = shift;
    $url =~ s#/$##;
    return $url;
}

sub extract_page_list{
    # accept args ref from outside
    my $worker	= shift;
    my $hook	= shift;
    my $params  = shift;
    my $pages	= shift;

    print "run extract_page_list ............\n";
    # create a html tree and parse
    my $web = $params->{web_page};
    eval{
        get_page_list( $web,undef,$pages );
    };
    if($@){
#        print Dumper $pages;
        return 0 unless scalar @$pages
    }
    return 1;
}

sub get_app_list{
    my $html      = shift;
    my $app_mark  = shift||'t';
    my $apps_href = shift;

    my $tree = new HTML::TreeBuilder;
    $tree->parse($html);

    my @nodes = $tree->look_down( class => $app_mark );
    Carp::croak('not find apps nodes by this mark name')
        unless ( scalar(@nodes) );

    map{
    my @tags = $_->find_by_tag_name('a');
    # <a target="_blank" href="/apk-3965-com.lingdong.quickpai.compareprice.ui.acitvity/">?ì??1o?????÷</a>
    return unless @tags;

    foreach my $tag(@tags){
        return unless ref($tag);
        my $link = $tag->attr('href');
        $link =~ m/-(\d+)/;
        $apps_href->{$1} = trim_url($url_base).$link;
    }
    } @nodes;

    $tree->delete;
    return
}

sub extract_app_from_feeder{
    # accept args ref from outside
    my $worker	= shift;
    my $hook	= shift;
    my $params  = shift;
    my $apps    = shift;
   
    return 0 unless ref( $params) eq 'HASH' ;
    return 0 unless ref(  $apps ) eq 'HASH' ;
    return 0 unless exists $params->{web_page};

    print "run extract_app_from_feeder_list ............\n";
    eval{
        my $html = $params->{web_page};
        get_app_list( $html,'t',$apps );
    };
    if($@){
        $apps = {};
        return 0
    }
    return 0 unless scalar(keys %{ $apps } );

    return 1;
}

sub get_author{
    return $AUTHOR;
}

sub get_trustgo_category_id{
    my $name = shift;
    return  $category_mapping{ shift @_ };
}

sub get_app_url{
    my $html = shift;

    # html_string
    # match app url from html 
    my $tree = new HTML::TreeBuilder;
    $tree->parse($html);
    my @nodes = $tree->look_down( class => 'down' );
    return 0 unless @nodes;
    my @tags = $nodes[0]->find_by_tag_name('img');
    my $src = $tags[0]->attr('src');

    # img string
    # <img src="/qrcode/18387.jpg">
    $tree->delete;

    if( $src =~ m{/(\d+)\.jpg}i ){
        return trim_url($url_base).'/soft/'.$1.'.html';
    }

    return undef;
}

sub get_icon{
    my $html = shift;
    
    my $tree = new HTML::TreeBuilder;
    $tree->parse($html);
#    return unless @nodes;

    #look down brief label;
    my @nodes = $tree->look_down( class => 'apptitle');
    return unless @nodes;

    my @tags = $nodes[0]->find_by_tag_name('img');
    my $icon = $url_base.$tags[0]->attr('src');

    # delete what I have done
    $tree->delete;
    return $icon || undef;
}

sub get_app_name{
    my $html = shift;
    my $mark = shift||'apptitle';
    
    my $tree = new HTML::TreeBuilder;
    $tree->parse($html);

    # find app name for app_info
    # html_string:
    # mark class = "qnav"
=pod
<div class="apptitle">
<img class="applo
<h1>MyBackup Pro:全能备份专家 3.0.0已付费版</h1>
=cut
    my @nodes = $tree->look_down( class => $mark );
    return unless @nodes;

    my @tags = $nodes[0]->find_by_tag_name('h1');
    my $app_name = $tags[0]->as_text;

    # delete what I ever done
    $tree->delete;
    return $app_name || undef;
}

sub get_price{ 
    return 0;
}

sub get_description{
    my $html = shift;

    if( $html =~ m{(应用详细介绍.*?)</div>}s ){
        #( my $desc = $1 ) = ~ s/[\000-\037]//g;
        my $desc = $1;
        $desc =~ s/[\000-\037]//g;
        $desc =~ s/<.+?>//g;
        #$desc =~ s#<a.+?</strong>##g;
        $desc =~ s#&ldquo#"#g;
        $desc =~ s#&rdquo#"#g;
        return $desc;
    }

    return 
}

sub get_size{
    my $html = shift;
    # mark is class => 'info'
    my $mark = shift||'appdetails';

=pod
<span>
<em>大小：</em>
3.06 MB
</span>
=cut
    if( $html =~ m{em>大小.*?(\d.*?MB)}s ){
        my $size = $1;
        return kb_m($size);
    }
    return 
}

sub get_total_install_times{
    my $html = shift;
=pod
<span class="alt">
约2100次下载，
<a target="_self" href="#comment">11次评论</a>
=cut
    if( $html =~ m/(\d+)次下载/s){
        my $install_times = $1;
        return $install_times;
    }

    return undef;
}

sub get_last_update{
    my $html = shift;
=pod
<h2>更新记录 · · ·</h2>
<div class="changelog">
<span>
2010-09-04
<em>收录版本：0.7付费版</em>
=cut
    my $tree = new HTML::TreeBuilder;
    $tree->parse($html);
    my @nodes = $tree->look_down( class => 'changelog' );
    return unless @nodes;
    
    my $content = $nodes[0]->as_text;
    $tree->delete;

    if(my @date = $content =~ m/(\d{4}-\d{2}-\d{2})/sg){
        my $last_update = $date[-1];
        return $last_update;
    }
    return ;
}

sub get_cookie{
    my $cookie_file = shift;
    my $login_html  = get($login_url);

    my %info = $login_html =~ m{<input type="hidden" name="(.+?)" value="(.*?)"}sg;
    my $cookie_jar = HTTP::Cookies->new(
        file        => $cookie_file,
        autosave    => 1,
    );

    my $ua = LWP::UserAgent->new;
    my $username ="jinyiming321";
    my $pwd ="19841002";
    
    $ua->cookie_jar($cookie_jar);
    $ua->agent("Mozilla/4.0");
    #$res = $ua->get($url);
    
    # post form
    $ua->cookie_jar($cookie_jar);
    push @{$ua->requests_redirectable}, 'POST';
    my $res = $ua->post(
        $login_url,
        [
            login       => 'jinyiming321',
            pwd         => '19841002',
            op          => $info{op},
            formhash    => $info{formhash},
            forward     => '',
            postsubmit  => $info{postsubmit},
            remember    => 1
        ]
    );
=pod
    my $apk_download_url = "http://www.coolapk.com/dl";
    $res = $ua->post( 
        $apk_download_url,[
            sid     => 3,
            inajax  => 1,
            op      => 'download',
            d       => 1316691530671,# a ad id,task easy
        ]
    );
=cut
    if( Encode::decode_utf8($res->content) =~/退出登录/s){
        return 1;
    }

    return 
}

sub get_apk_url{
    my $html = shift;

    # <img src="/qr.php?sid=MjU0NiwxOCwxNiwxLCw4M2RlMmExNg==" class="qrcode">
    # <img class="qrcode" src="/qr.php?sid=MjU0NiwxOCwxNiwxLCw4M2RlMmExNg==">
    $html =~ m{img class="qrcode".*?sid=(.+?)"}s;
    my $sid = $1;
    # save sid for get_permission's sid
    {
        no strict 'refs';
        ${ __PACKAGE__."::"."SID" } = $sid;
    }

    unless( -e $cookie_file ){
        Carp::croak("can't get cookie from coolapk")
            unless get_cookie($cookie_file);
    }

    my $ua = LWP::UserAgent->new;
    my $cookie_jar = HTTP::Cookies->new(
         file => $cookie_file,
    );
    $cookie_jar->load($cookie_file);
    $ua->cookie_jar($cookie_jar);
    $ua->agent("Mozilla/4.0");
    my $retry = 0;

    DOWN_LOAD_APK:
    my $apk_download_url = "http://www.coolapk.com/dl";
    # http://www.coolapk.com/dl?sid=MjU0NiwxOCwxNiwxLCw4M2RlMmExNg==&inajax=1&op=download&d=1316691530671
    # header
    #   d	1316691530671
    #   inajax	1
    #   op	download
    #   sid	MjU0NiwxOCwxNiwxLCw4M2RlMmExNg==
    # 
    my $res = $ua->post( 
        $apk_download_url,[
            sid     => $sid,
            inajax  => 1,
            op      => 'download',
            d       => 1316691530671,# a ad id,task easy
        ]
    );
    if( $res->status_line =~ m/200/ ){
		# window.location.href='\/dl?dl=1&sid=&authimg=&hash=4ef3b755'
        if( $res->content =~ m/href='(.+?)'/s ){
            my $download = $1;
            $download =~ s/\\//g;
			$download =~ s/sid=/'sid='.$sid/e;
            return $url_base.$download;
        }
    }else{
        get_cookie($cookie_file) && goto DOWN_LOAD_APK unless $retry;
        ++$retry;
        return;
    }
}

sub get_official_rating_stars{
    my $html  = shift;
    # find stars for app
    # html_string:
=pod
<span class="ratingstars" rank="4.0" star="4" style="background-position: 0px -80px;">
    <a class="s1" params="id=3446&star=1" onclick="doAjaxPost(this,'voteapk');" href="javascript:;"></a>
    <a class="s2" params="id=3446&star=2" onclick="doAjaxPost(this,'voteapk');" href="javascript:;"></a>
    <a class="s3" params="id=3446&star=3" onclick="doAjaxPost(this,'voteapk');" href="javascript:;"></a>
    <a class="s4" params="id=3446&star=4" onclick="doAjaxPost(this,'voteapk');" href="javascript:;"></a>
    <a class="s5" params="id=3446&star=5" onclick="doAjaxPost(this,'voteapk');" href="javascript:;"></a>
    <em>4.0</em>
</span>
=cut
    my $tree = new HTML::TreeBuilder;
    $tree->parse($html);

    my @nodes = $tree->look_down( class => 'ratingstars' );
    return unless @nodes;

    my @tags = $nodes[0]->find_by_tag_name('em');
    my $rating_star = $tags[0]->as_text();

    return $rating_star ||undef;
}

sub kb_m{
    my $size = shift;

    # MB -> KB 
    $size = $1*1024 if( $size =~ s/([\d\.]+)(.*MB.*)/$1/i );
    $size = $1  if( $size =~ s/([\d\.]+)(.*KB.*)/$1/i );

    # return byte
    return int($size*1024);
}

sub get_official_category{
    my $html = shift;

    my $tree = new HTML::TreeBuilder;
    $tree->parse($html);
=pod
<div id="navbar">
<a href="http://www.coolapk.com/">酷安网</a>
&gt;
<a href="/apk/">Android软件</a>
&gt;
<a href="/apk/themes/">主题美化</a>
&gt; Go Launcher桌面 1.41
=cut

    my @nodes = $tree->look_down( id => 'navbar' );
    return unless @nodes;
    
    my @tags = $nodes[0]->find_by_tag_name('a');
    my $official_category = $tags[2]->as_text;

    return $official_category||'unknown';
}

#-------------------------------------------------------------

sub get_current_version{
    my $html = shift;
    #print $version_s;
    my $tree = new HTML::TreeBuilder;
    $tree->parse($html);
    my @nodes = $tree->look_down( class => 'appdetails');
    return unless @nodes;
    my $text = $nodes[0]->as_text;
    $text =~ m/版本(.*?)([0-9\.]+)/s;
    return $2||undef;
}

sub get_app_qr{
    my $html = shift;

    # html sinppet
=pod
<img src="/qr.php?sid=MzQ0NiwxOCw2LDEsLGNiNDdkOTcx" class="qrcode">
=cut
    my $tree = new HTML::TreeBuilder;
    $tree->parse($html);
    my @nodes = $tree->look_down( class => 'qrcode' );
    return 0 unless @nodes;

    # fetch img from this snippet
    my @tags = $nodes[0]->find_by_tag_name('img');
    my $qr = $tags[0]->attr('src');
    $tree->delete;

    return trim_url($url_base).$qr||undef;
}
sub get_screenshot{
    my $html = shift;
    
    #var $imgs = ['/~/uploads/allimg/110107/2_110107091032_1.jpg','/~/uploads/allimg/110107/2_110107091032_2.jpg'];
    if( $html =~ m/var \$imgs = \[(.*?)\]/s){
        my @screenshot = $1 =~ m/'(.+?)'/g;
        return [ map{ $url_base.$_ } @screenshot ];
    }

    return ;
    # screenshot is 'screen-div'
    # fetch src
    # html_string
=pod
=cut
    my $tree = new HTML::TreeBuilder;
    $tree->parse($html);
    # screencount
    my @nodes = $tree->look_down( id => 'screencount');
    (my $count = $nodes[0]->as_text) =~ m{\d+/(\d+)};
    $count = $1;
=pod
<div id=> 'screenpreview'
<img alt="截图预览" src="/~/uploads/allimg/110906/2_110906145600_1.jpg" style="width: 240px; display: inline; height: 360px;">
=cut
    my @img= [$tree->look_down( id => 'screenpreview' )]->[0]
        ->find_by_tag_name('img');
    my $src = $img[0]->attr('src');
    return [ map{
            $src =~ s#(\d+)(?=jpg)#$count#e;
            trim_url($url_base).$src;
        }(1..$count)
    ]
}


#-------------------------------------------------------------
sub get_permission{
    my $html = shift;

    # the list needed to return 
    my $permission = [];
    my $sid;
    my $app_url;
    my $app_id;
    {
        no strict 'refs';
        $sid = ${__PACKAGE__."::"."SID"};
        ($app_url = ${__PACKAGE__."::"."APP_URL"}) =~ m/(\d+)/;
        $app_id = $1;
    }
    unless( -e $cookie_file ){
        return unless get_cookie($cookie_file);
    }

    my $ua = LWP::UserAgent->new;
    my $cookie_jar = HTTP::Cookies->new(
        file    => $cookie_file,
    );
    $cookie_jar->load($cookie_file);
    $ua->cookie_jar($cookie_jar);
    $ua->agent("Mozilla/4.0");
    my $retry = 0;

    DOWN_LOAD_PERM:
    # http://www.coolapk.com/do.php?ac=ajax&inajax=1&op=viewpermissions&d=1316693842750
    # header
    #   d	1316691530671
    #   inajax	1
    #   op	download
    #   sid	MjU0NiwxOCwxNiwxLCw4M2RlMmExNg==
    #
    my $res = $ua->post( 
        $permission_url,
        [
            id=> $app_id,
        ]
    );
    if( $res->status_line =~ m/200/ ){
        # TODO GET PERMISSION
        if( @{$permission} = $res->content =~ m{(android\.permission\..+?)<}sg){
            return $permission;
        }
        return 
    }else{
        get_cookie && goto DOWN_LOAD_APK unless $retry;
        ++$retry;
        return;
    }

    return 
}

sub get_related_app{
    my $html = shift;
    
    # a related apps 
    my $related_apps = [];
    # create a empty html tree
    my $tree = new HTML::TreeBuilder;
    $tree->parse($html);

=pod
div class="appinfo">
    <p>
    <em>免费</em>
    <strong>
    <a target="_blank" href="/apk-4018-com.icbc/">工行手机银行 1.0.0.1</a>
</strong>
=cut
    my @nodes = $tree->look_down( class => 'appinfo');
    return unless @nodes;

    for(@nodes){
        push (
            @{ $related_apps },
            $url_base.[$_->find_by_tag_name('a')]->[0]->attr('href')
        );
    }

    return  $related_apps;
}

sub extract_app_info
{
    # accept args ref from outside
    my $worker	 = shift;
    my $hook	 = shift;
    my $html     = shift;
    my $app_info = shift;
    
    { 
        no strict 'refs';
        ${ __PACKAGE__."::"."APP_URL" } = $app_info->{app_url};
    }

    # create a html tree and parse
    print "extract_app_info  run \n";

    eval{
        # TODO get note 'not find'
        {
            no strict 'refs';
            foreach my $meta( @app_info_list ){
                # dymic function invoke
                # 'get_author' => sub get_author
                # 'get_price'  => sub get_price
                next unless ref($app_map_func{$meta}) eq 'CODE';
                my $ret = &{ $app_map_func{$meta} }($html);
                if( defined($ret) ){
                    $app_info->{$meta} = $ret;
                }
            }

            if (defined($category_mapping{$app_info->{official_category}})){
                $app_info->{trustgo_category_id} 
                    =$category_mapping{$app_info->{official_category}};
            }else{
                my $str="Out of TrustGo category:".$app_info->{app_url_md5};
                open(OUT,">>/root/outofcat.txt");
                print OUT "$str\n";
                close(OUT);
                die "Out of Category";
            }
        }
    };
#    use Data::Dumper;
#    print Dumper $app_info;

    $app_info->{status} = 'success';
    if($@){
        $app_info->{status} = 'fail';
    }

    return scalar %{$app_info};
}

sub get_content{
    my $html = shift;
    use FileHandle;
    use open ':utf8';
    my $content = do{
        local $/='</html>';
        my $fh = new FileHandle($html)||die $@;
        <$fh>
    };

    return $content;
}

sub get_system_requirement{
    my $html = shift;

    {
        no strict 'refs';
=pod
<em>支持ROM：</em>
1.6/2.0/2.1/2.2/2.3
=cut
        if($html =~ m{支持ROM.+?(\d+.+?)</span>}s){
            my $rom_version = $1;
            my @versions = split('/',$rom_version);
            if( scalar @versions ){
                ${ __PACKAGE__."::"."min_os_version" } = $versions[0];
                ${ __PACKAGE__."::"."max_os_version" } = $versions[-1];
            }
            return $rom_version;
        }
    }
    return
}

sub get_min_os_version{
    {
        no strict 'refs';
        my $min_os_version = ${ __PACKAGE__."::"."min_os_version" };
        return $min_os_version || undef;
    }
}

sub get_max_os_version{
    {
        no strict 'refs';
        my $max_os_version = ${ __PACKAGE__."::"."max_os_version" };
        return $max_os_version || undef;
    }
}

sub get_official_rating_times{
    my $html = shift;
   
    my $tree = new HTML::TreeBuilder;
    $tree->parse($html);
    # <span class="ratinglabel">135个评分：</span>
    my @nodes = $tree->look_down( class => 'ratinglabel' );
    return unless @nodes;

    $nodes[0]->as_text =~ m/(\d+)/;
    my $rating_times = $1;
    $tree->delete;
    return $rating_times||undef;
}

sub run{
    use LWP::Simple;
    #my $content = get('http://www.coolapk.com/apk-3433-panso.remword/');
    # my $content = get('http://www.coolapk.com/apk-2450-com.runningfox.humor/');
    my $content = get('http://www.coolapk.com/game/shoot/');
    my @pages = ();
    extract_page_list(undef,undef,{web_page=>$content},\@pages);
    use Data::Dumper;
    print Dumper \@pages;
    exit 0;

    use Data::Dumper;
    print Dumper \@pages;
    
    my $apps = {};
    foreach my $page( @pages ){
        $content = get($page);
        &extract_app_from_feeder(undef,undef,{web_page=>$content},$apps);
    }
    my $app_num = scalar (keys %{$apps});
    print Dumper $apps;
    print "app_num is $app_num\n";
    exit 0;
    my $html = 'coolapk-htc.html';
    use FileHandle;
    my $fh = new FileHandle(">>$html")||die $@;
    $fh->print($content);
    $fh->close;
    my $app_info = {};
    $app_info->{app_url} = 'http://www.coolapk.com/apk-3433-panso.remword/';
    extract_app_info( undef,undef,$content,$app_info );
    use Data::Dumper;
    print Dumper $app_info;
    #    print "key => ".decode_utf8($app_info->{$_}\n";
}
sub download_app_apk 
{
    my $self    = shift;
    my $hook_name  = shift;
    my $apk_info= shift;

    my $apk_file;
    my $md5 =   $apk_info->{'app_url_md5'};
    my $apk_dir= $self->{'TOP_DIR'}.'/'. get_app_dir( $self->getAttribute('MARKET'),$md5).'/apk';
    my $cookie_jar = HTTP::Cookies->new(
         file => $cookie_file,
    );
    $cookie_jar->load($cookie_file);

    my $downloader  = new AMMS::Downloader;
    $downloader->header({Referer=>$apk_info->{'app_url'}});
    $downloader->{USERAGENT}->cookie_jar($cookie_jar);

    if( $apk_info->{price} ne '0' ){
        $apk_info->{'status'}='paid';
        return 1;
    }
    eval { 
        rmtree $apk_dir if -e $apk_dir;
        mkpath $apk_dir;
    };
    if ( $@ )
    {
        $self->{ 'LOGGER'}->error( sprintf("fail to create directory,App ID:%s,Error: %s",
                                    $md5,$@)
                                 );
        $apk_info->{'status'}='fail';
        return 0;
    }

    $downloader->timeout($self->{'CONFIG_HANDLE'}->getAttribute('ApkDownloadMaxTime'));
    $apk_file=$downloader->download_to_disk($apk_info->{'apk_url'},$apk_dir,undef);
    if (!$downloader->is_success)
    {
        $apk_info->{'status'}='fail';
        return 0;
    }

    my $unique_name=md5_hex("$apk_dir/$apk_file")."__".$apk_file;

    rename("$apk_dir/$apk_file","$apk_dir/$unique_name");


    $apk_info->{'status'}='success';
    $apk_info->{'app_unique_name'} = $unique_name;

    return 1;
}

1;
#&run;

__END__



