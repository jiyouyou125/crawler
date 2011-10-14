#!/usr/bin/perl 
#==========================================================================
#         FILE: liqu.pl
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
#==========================================================================

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

my $market      = 'www.liqucn.com';
my $url_base    = 'www.liqucn.com';
#my $downloader  = new AMMS::Downloader;
my $login_url   = '';
my $cookie_file = '';

my $tree ;

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

our %category_mapping=(
    #手机安全
    "杀毒"        => 2302,
    "加密"        => 2304,
    "防盗"        => 2305,
    "备份"        => 2200,
    "防火墙"      => 2301,

    # 掌上资讯
    "导航"        => 2100,
    "炒股"        => 202,
    "阅读"        => 2500,
    "学习"        => 504, 
    "天气"        => 24,
    "字典"        => 103,
    "保健"        => 902,
    "占卜"        => 19,
    "购物"        => 1701,
    "娱乐"        => 6,
    "其他"        => 0,

    # 网络通讯
    "交友"        => "18,400",
    "浏览"        => 2210,
    "通讯"        => 2209,
    "邮件"        => 401,
    # 系统增强
    "输入法"      => 2217,
    "美化"        => 1203,
    "管理"        => "220,222",
    "清理"        => 2206,
    "下载"        => 2212,
    "同步"        => 2216,
    "刷机"        => 22,

    # 拍照音乐
    "音乐"        => "703,704,709",
    "视频"        => "707,708",
    "拍照"        => 15,

    # 办公
    "文档"        => '1604,1608',
    "日程"        => 1605,
    "名片"        => 1907,

    # 游戏
    "角色"        => 812,
    "动作"        => 823,
    "射击"        => 821,
    "竞速"        => 811,
    "益智"        => 810,
    "棋牌"        => "802,803",
    "格斗"        => 825,
    "冒险"        => 800,
    "策略"        => 815,
    "体育"        => 814,
    "养成"        => 815,
    "休闲"        => 818,
    "经营"        => 815,
    "数据包"      => 8,
    "即时"        => 822,
    "回合"        => 822,
    "GBA"         => 813,
    "NES(FC)"     => 813,
    "MD"          => 813,
    "SFC"         => 813,
    "GB/GBC"      => 813,
);
=pod
    GBA NES(FC) MD SFC
        GB/GBC 
=cut
        

# define a app_info mapping
# because trustgo_category_id is related with official_category
# so i remove it from this mapping
our %app_map_func = (
        author                  => \&get_author, 
        app_name                => \&get_app_name,
        current_version         => \&get_current_version,
        icon                    => \&get_icon,
        price                   => \&get_price,
        system_requirement      => '', # no find
        min_os_version          => '', # not find
        max_os_version          => '', # not find
        resolution              => '', # not find
        last_update             => \&get_last_update,
        size                    => \&get_size,
        official_rating_stars   => \&get_official_rating_stars,
        official_rating_times   => '', #can't get it
        app_qr                  => \&get_app_qr,
        note                    => '', #not find
        apk_url                 => \&get_apk_url, 
        total_install_times     => \&get_total_install_times,
        description             => \&get_description,
        official_category       => \&get_official_category,
        trustgo_category_id     => '',# mapping
        related_app             => \&get_related_app,
        screenshot              => \&get_screenshot,
        permission              => \&get_permission,
        status                  => '',
);

our @app_info_list = qw(
        author                  
        app_name
        current_version
        icon                    
        price                   
        resolution              
        last_update             
        size                    
        apk_url                 
        total_install_times     
        description             
        official_category       
        trustgo_category_id     
        related_app             
        screenshot               
        status                  
);

our $AUTHOR     = '历趣网';
if( $ARGV[-1] eq 'debug' ){
    &run;
}
# check args 
unless( $task_type && $task_id && $conf_file ){
    die $usage;
}

#&run;

# check configure
die "\nplease check config parameter\n" 
    unless init_gloabl_variable( $conf_file );


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

sub get_page_list{
    my $html        = shift;
    my $params      = shift;
    my $pages       = shift;

    my $tree = new HTML::TreeBuilder;
    $tree->parse($html);
    $tree->eof;

=pod
    <li class="page_tab">1</li>
    <li class="page_nor">
    <li class="page_nor">
    <a href="http://www.liqucn.com/os/android/yx/c/339/index_162.shtml">3</a>
=cut 
    my $page_tab = $tree->look_down( class => 'page_tab');
    return unless $page_tab;

    #my $index = 'http://www.liqucn.com/os/android/yx/index_268.shtml'
    push @{ $pages },$params->{base_url};
    my $total_page_num = 0;

    if( my @nodes = $tree->find_by_attribute( class => 'page_nor' ) ){
        my $last_page_url 
            = ($nodes[0]->find_by_tag_name('a') )[0]->attr('href');
        if( $last_page_url =~ m/(.*?)index_(\d+)\.shtml/ ){
            $total_page_num = $2;
        }
    }

    $tree->delete;
    return unless $total_page_num;

    map{
        push @{ $pages },trim_url($params->{base_url})."/index_$_.shtml"
    } ( 1..$total_page_num );
    
    return  1;
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
        get_page_list( $web,$params,$pages );
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
    my $base_url  = shift;

    my $tree = new HTML::TreeBuilder;
    $tree->parse($html);
    $tree->eof;

    my @nodes = $tree->look_down( class => 'show_text');
    return  unless @nodes;

    for(@nodes){
        next unless ref($_);
        my $url = ( $_->find_by_tag_name('a') )[0]->attr('href');
        if( $url =~ m/(\d+)\.shtml/){
            $apps_href->{$1} = $url;
        }
    }

    $tree->delete;
    return 1
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
        get_app_list( $html,undef,$apps,$params->{base_url} );
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
    my $app_info = pop;

    return  $app_info->{app_url};
}

sub get_icon{
    my $html = shift;
    
    $tree->parse($html);
#    return unless @nodes;

    #look down brief label;
    my @nodes = $tree->look_down( id => 'screenshot_1');
    return unless @nodes;

    my $icon = $nodes[0]->attr('src');
    return $icon;
}

sub get_app_name{
    my $html = shift;
    my @nodes =  $tree->look_down( class => 'soft_down');
    my $tag = ($nodes[0]->find_by_tag_name('h2'))[0];
    # <div class="soft_down">
    # <h2>360手机卫士1.9简介</h2
    if( $tag->as_text =~ m{(.+?)简介}s ){
        my $app_name = $1;
        if( $app_name =~ m/([\d\.]+)$/ ){
            print "version is $1\n";
            my $version = $1;
            $app_map_func{current_version} = sub{
                return $version;
            }
        }
        return $app_name
    }
    return
}

sub get_price{ 
    return 0;
}

sub get_description{
    my $html = shift;
    my @nodes = $tree->look_down( id => 'p_content' );
    my $desc = $nodes[0]->as_text;

    $desc =~ s/\r//g;
    $desc =~ s/\n//g;
    $desc =~ s/\s/ /g;
    return  $desc;
}

sub get_size{
    my $html = shift;

    my @nodes = $tree->look_down(class => 'down_btn');
    return unless @nodes;

    my @tags = $nodes[0]->find_by_tag_name('span');
    my $size = kb_m($tags[0]->as_text);
    return  $size||"未知"
}

sub get_total_install_times{
    my $html = shift;

    if( $html =~ m/下载次数.*?(\d+)/s ){
        return $1;
    }
    return undef;
}

sub get_last_update{
    my $html = shift;
    my $last_update;
    if( $html =~ m/更新时间(.*?)(\d{4}-\d{2}-\d{2})/s ){
        $last_update = $2;
        return $last_update;
    }
    return 
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
    my $app_info = pop;
    my $apk_url;
    
    # refer : http://www.liqucn.com/os/android/rj/11114.shtml
#    my @nodes = $tree->look_down( 
#   # find html tree
    
    my @nodes = $tree->look_down( id => 'content_mobile_href');
    my $link = $nodes[0]->attr('href');
    my $ua = LWP::UserAgent->new(keep_alive => 1);
    $ua->max_redirect(0);
    my $res = $ua->get($link);
    $apk_url = $res->header('location');

    my $downloader = new AMMS::Downloader;
    $downloader->header( { Referer => $app_info->{app_url} } );  
    my $content = $downloader->download(
        "http://www.liqucn.com/api/ajax.php?".
        "action=dialog&type=downloadDialog"
        );

    my $root = new HTML::TreeBuilder;
    $root->parse( Encode::decode_utf8($content) );

    @nodes = $root->look_down( id => 'qr_code_img');
    return unless @nodes;
    #<img id="qr_code_img"
    #src="http://chart.apis.google.com/chart?chs=150x150&cht=qr&chld=Q|0&chl=">
    my $src = $nodes[0]->attr('src');
    return $apk_url;
}

sub get_official_rating_stars{
    return 0;
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
    my $app_info = shift;

    my @nodes = $tree->look_down( class => 'subNav2');
    return unless @nodes;

    my @tags = $nodes[0]->find_by_tag_name('a');
    my $official_category = $tags[-1]->as_text;

    return $official_category||undef;
}

#-------------------------------------------------------------

sub get_current_version{
    my $html     = shift;
    my $app_info = shift;

    if($html =~ m/([\d\.]+)简介/s){
        my $version = $1;
    }

    return "未知"
}

sub get_app_qr{
}

sub get_screenshot{
    my $html = shift;
    my $screenshot = [];

    my @nodes = $tree->look_down( class => 'play_top');
    return unless @nodes;

    my @imgs = $nodes[0]->find_by_tag_name('img');
    push @{$screenshot},$_->attr('src') for @imgs;
    
    return $screenshot;
}

#-------------------------------------------------------------
sub get_permission{
    my $html = shift;

    # the list needed to return 
    my $permission = [];
    return 
}

sub get_related_app{
    my $html = shift;
    
    my $related_apps = [];
    # create a empty html tree
    my @nodes = $tree->look_down(class => 'top_text top_line');
    return unless @nodes;
    for(@nodes){
        my $tag = [$_->find_by_tag_name('a')]->[0];
        next unless ref($tag);
        push @{ $related_apps },$tag->attr('href');
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
    

    # create a html tree and parse
    print "extract_app_info  run \n";
    $tree = new HTML::TreeBuilder;
    $tree->parse($html) or die "html is empty";
    $tree->eof;

    eval{
        # TODO get note 'not find'
        {
            foreach my $meta( @app_info_list ){
                # dymic function invoke
                # 'get_author' => sub get_author
                # 'get_price'  => sub get_price
                next unless ref($app_map_func{$meta}) eq 'CODE';
                my $ret = &{ $app_map_func{$meta} }($html,$app_info);
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

    $app_info->{status} = 'success';
    if($@){
        $app_info->{status} = 'fail';
    }
    $tree->delete;

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

}

sub run{
    use LWP::Simple;

    #my $content = get('http://www.coolapk.com/apk-3433-panso.remword/');
    # my $content = get('http://www.coolapk.com/apk-2450-com.runningfox.humor/');
#    my $content = get('http://www.liqucn.com/os/android/yx/c/332/');
    my $content = get('http://www.liqucn.com/yx/10607.shtml');
    
    goto APP_INFO;
    my @pages = ();
    extract_page_list(undef,undef,{
            web_page => $content,
            base_url => 'http://www.liqucn.com/os/android/yx/c/332/',
            },
            \@pages
            );
    use Data::Dumper;
    print Dumper \@pages;

#$content = get('http://www.liqucn.com/os/android/yx/c/332/');
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
APP_INFO:
    my $app_info = {};
    $app_info->{app_url} = 'http://www.liqucn.com/os/android/rj/10737.shtml';
    $app_info->{app_url_md5} = '4esdfsdfs;fsd;fdf;';
    extract_app_info( undef,undef,$content,$app_info );
    use Data::Dumper;
#print Dumper $app_info;
    use Encode;
    my $desc = decode_utf8($app_info->{description});
    print $desc."\n";    
    #    print "key => ".decode_utf8($app_info->{$_}\n";
#    }
}

1;
#&run;

__END__



