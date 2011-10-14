#!/usr/bin/perl 
#===============================================================================
#         FILE: xda.pl
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
BEGIN{
    unless( $^O =~ m/win/i ){
        print "hello ";
        require AMMS::Util;
        require AMMS::AppFinder;
        require AMMS::Downloader;
        require AMMS::NewAppExtractor;
        require AMMS::UpdatedAppExtractor;
    }       
}



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

my $market      = 'http://android.xda.cn';
my $url_base    = "http://android.xda.cn";
#my $downloader  = new AMMS::Downloader;
my $login_url   = '';
my $cookie_file = '';

my $tree;
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
        icon                    => '',
        price                   => \&get_price,
        system_requirement      => '',
        min_os_version          => '',
        max_os_version          => '',
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

our $AUTHOR     = '未知';

if( $ARGV[-1] eq 'debug' ){
    &run;
    exit 0;
}

# check args 
unless( $task_type && $task_id && $conf_file ){
    die $usage;
}

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
    my $params      = shift;
    my $pages       = shift;

    my $tree = new HTML::TreeBuilder;
    $tree->parse($html);

    my @nodes = $tree->look_down( class => 'pageinfo');
    return unless @nodes;

    my $page_num = ( $nodes[0]->find_by_tag_name('strong') )[0]->as_text;
    return unless $page_num;

    my @list = $tree->look_down( class => 'pagelist');
    my $link = ( $list[0]->find_by_tag_name('a') )[0]->attr('href');

    $tree->delete;
    $link =~ s/(\d+)\.html/'$num'."_.html"/e;

    map{
        (my $temp = $link) =~ s/\$num/$_/;
        push @{ $pages },$temp;
    } (1..$page_num);
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
    my $params    = shift;
    my $apps_href = shift;

    my $tree = new HTML::TreeBuilder;
    $tree->parse($html);
    # content_left_right_child_center
    my @nodes = $tree->look_down( class => 'content_left_right_child_center');
    Carp::croak('not find apps nodes by this mark name')
        unless ( scalar(@nodes) );
    
    my @tags = $nodes[0]->find_by_tag_name('a');

    for(@tags){
        next unless ref($_);
        my $href = $_->attr('href');
        if($href =~ m/(\d+)\.html/){
            $apps_href->{$1} = $href;
        }
    }
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
        get_app_list( $html,$params,$apps );
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
    $tree->delete;

}


sub get_app_name{
    my $html = shift;
    my $app_info = shift;
    
    my @nodes = $tree->look_down( id =>'sname');
    return unless @nodes;

    my $app_name = $nodes[0]->as_text;
    $app_name =~ s/\r//sg;
    $app_name =~ s/\n//sg;
    
    return $app_name;
}

sub get_price{ 
    my $html = shift;
    
    if( $html =~ m{是否收费.*?span>.*?(\w+)}s ){
        retrun $1;
    }
    return 0;
}

sub get_description{
    my $html = shift;
    my $app_info = shift;

    my @nodes = $tree->look_down( class => 'content');
    return unless @nodes;

    my @tags = $nodes[0]->find_by_tag_name('p');
    my $content = $tags[0]->as_text;

    return $content;
}

sub get_size{
    my $html = shift;
    return 
}

sub get_total_install_times{
    my $html = shift;
    my $app_info = shift;

    my @nodes = $tree->look_down( class => 'ttnum' );
    return unless @nodes;

    my $times = $nodes[0]->as_text;
    return $times
}

sub get_last_update{
    my $html = shift;
    my $date;
    
    if( $html =~ m/软件大小.*?([\d\.]+.+?)</s ){
        my $size = $1;
        $app_map_func{size} = sub{
            return kb_m($size);
        }
    }
    # ★★★☆☆
    if( $html =~ m/软件等级.*?<span>(.+?)</s){
        my $star = $1;
        $app_map_func{official_rating_stars} = sub{
            return $star;
        }
    }
    if( $html =~ m/发布时间.*?(\d{4}-\d{2}-\d{2})/s ){
        $date = $1;
    }
    if( $html =~ m/下载次数.*?(\d+)/s ){
        my $download_times = $1;
        $app_map_func{total_install_times} = sub{
            return $download_times
        }
    }
    return $date;
}

sub get_apk_url{
    my $html     = shift;
    my $app_info = shift;

    my @nodes = $tree->look_down( class => 'downurllist');
    return unless @nodes;

    my $download_url = ( $nodes[0]->find_by_tag_name('a') )[0]->attr('href');
    return $download_url;
}

sub get_official_rating_stars{
    my $html  = shift;
    my $app_info = shift;

    my @nodes = $tree->look_down( class => 'num');
    return unless @nodes;

    my @tags = $nodes[0]->find_by_tag_name('span');

    my $stars = join(
        "",
        $tags[0]->as_text,
        $tags[1]->as_text,
    );

    return $stars;
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

}

#-------------------------------------------------------------

sub get_current_version{
    my $html = shift;
    my $app_info = shift;

    my @nodes = $tree->look_down( id => 'version' );
    return unless @nodes;

    my $version = ($nodes[0]->find_by_tag_name('strong'))[0]->as_text;
    $version =~ s/(//;
    $version =~ s/)//;

    return $version||undef;
}   

sub get_app_qr{
    my $html = shift;
    return 
}
sub get_screenshot{
    my $html = shift;
    my $app_info = shift;
    
    my $screenshot = [];
    my @nodes = $tree->look_down( class => 'softpic');
    return unless @nodes;
    my @imgs = $nodes[0]->find_by_tag_name('img');
    push @{$screenshot},$_->attr('src') for @imgs;
    return  $screenshot;
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
    my $app_info = shift;

    my $related_apps = [];
    my @nodes = $tree->look_down( class => 'list3 listimg' );
    return unless @nodes;

    my @tags = $nodes[0]->find_by_tag_name('a');
    for(@tags){
        push @$related_apps,trim_url($url_base).$_->attr('href') ;
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
    
    $tree = new HTML::TreeBuilder;
    $tree->parse($html);
    $tree->eof;
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
                my $ret = &{ $app_map_func{$meta} }($html,$app_info);
                if( $meta=~ m/star/ ){
                    print 'star is '.$ret."\n";
                }
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
    $tree->delete;

    $app_info->{status} = 'success';
    if($@){
        $app_info->{status} = 'fail';
    }

    return scalar %{$app_info};
}

sub get_content{
    my $html = shift;
    use FileHandle;
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
    my $html = shift;
   
    my $tree = new HTML::TreeBuilder;
    $tree->parse($html);
    # <span class="ratinglabel">135个评分：</span>
    my @nodes = $tree->look_down( class => 'ratinglabel' );
    return unless @nodes;

}

sub run{
    use LWP::Simple;
#    my $content = get('http://www.android168.com/apk/');
    my $content = get_content('168an.html');
    my @pages = ();
    extract_page_list(undef,undef,{
                               web_page=>$content,
                               base_url=> 'http://www.android168.com/apk/',
                               },\@pages);
    use Data::Dumper;
    print Dumper \@pages;
    
    my $apps = {};
#    foreach my $page( @pages ){
    #$content = get_content('app_list.html')
    &extract_app_from_feeder(undef,undef,{web_page=>$content},$apps);
    my $app_num = scalar (keys %{$apps});
    print Dumper $apps;
    print "app_num is $app_num\n";
    my $app_info = {};
    use Encode;
    $app_info->{app_url} = 'http://www.coolapk.com/apk-3433-panso.remword/';
    $content = decode('gb2312',get_content("168app.html"));
        
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



