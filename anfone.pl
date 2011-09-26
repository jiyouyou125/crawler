#!/usr/bin/perl 
#===============================================================================
#
#         FILE: anfone.pl
#        USAGE: ./anfone.pl  
#  DESCRIPTION: 
#      This is a program,which is a adaptor for the crawler of amms system,
# it can parse html meta data and support extract_page_list,extract_app_from_feeder,
# extract_app_info.Somewhere used HTML::TreeBuilder to parse html tree, handle 
# description,stars... with regular expression.
#
# REQUIREMENTS: HTML::TreeBuilder,AMMS::UpdatedAppExtractor,AMMS::Downloader,
#               AMMS::NewAppExtractor,AMMS::AppFinder,AMMS::Util
#         BUGS: send email to me, if there is any bugs.
#        NOTES: add support for related app,screenshot,
#       AUTHOR: James King, jinyiming456@gmail.com
#      VERSION: 1.0
#      CREATED: 2011/9/19 0:10:31
#===============================================================================

use strict;
use warnings;

BEGIN{unshift(@INC, $1) if ($0=~m/(.+)\//);}
use strict;
use utf8;
use warnings;
use HTML::TreeBuilder;
use Carp ;

use AMMS::Util;
use AMMS::AppFinder;
use AMMS::Downloader;
use AMMS::NewAppExtractor;
use AMMS::UpdatedAppExtractor;
require Exporter;
our @ISA     = qw(Exporter);
our @EXPORT  = qw(
    extract_page_list 
    extract_app_from_feeder 
    extract_app_info
    trim_url 
    get_content 
    get_page_list 
    get_current_version 
    get_official_rating_stars
    get_official_category 
    get_price 
    get_description 
    get_app_name 
    get_app_list 
    get_price 
    get_related_app 
    get_permission 
    get_last_update 
    get_total_install_times
    get_trustgo_category_id 
    get_size 
    get_icon 
    get_app_qr
);

my $task_type   = $ARGV[0];
my $task_id     = $ARGV[1];
my $conf_file   = $ARGV[2];

my $market      = 'www.anfone.com';
my $url_base    = 'http://anfone.com';
#my $downloader  = new AMMS::Downloader;

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

# define a app_info mapping
# because trustgo_category_id is related with official_category
# so i remove it from this mapping
# modify record :
# 	2011-09-19 add support for screenshot related_app official_rating_starts
our @app_info_list = qw(
    author 
    app_name 
    official_category 
    current_version 
    size 
    price 
    description
    apk_url 
    last_update 
    total_install_times 
    app_qr
    permission
    screenshot
    official_rating_stars
    related_app
    icon
);

our %category_mapping=(
    "系统管理"    => 2206,
    "网络浏览"    => 2210,
    "影音媒体"    => 7,
    "文字输入"    => 2217,
    "安全防护"    => 23,
    "社区聊天"    => "400,18",
    "信息查询"    => 22,
    "导航地图"    => "13,2105",
    "通讯辅助"    => 2209,
    "阅读资讯"    => "14,1",
    "生活常用"    => 19,
    "财务工具"    => 2, 
    "学习办公"    => "5,16",
    # TODO sure class?
    "其他分类"    => 0,
    "主题图像"    => 1203,
    "棋牌游戏"    => 802,
    "益智休闲"    => 806,
    "体育运动"    => 814,
    "竞速游戏"    => 811,
    "射击游戏"    => 821,
    "角色扮演"    => 812,
    "冒险游戏"    => 800,
    "模拟经营"    => 813,
    "策略塔防"    => 815,
    "养成游戏"    => 813,
    "格斗游戏"    => 825,
    "飞行游戏"    => 826,
    "其他游戏"    => 8,
    "音乐游戏"    => 809,
    "动作游戏"    => 823,
	);

our $PAGE_MARK  = 'pagebar';
our $IMG        = 'img';
our $SRC        = 'src';
our $LINK_TAG   = 'a';
our $LINK_HREF  = 'href';
our $APPS_MARK  = 'box-lr20';
our $APP_MARK   = 'col2';
our $AUTHOR     = '安丰网';
our $ICON_MARK  = 'brief';
our $DESC_MARK  = 'screen';
our $SIZE_MARK  = 'info';

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

sub FIRST_NODE			(){		0		}

sub init_html_parser{
    my $html = shift;
    my $tree = new HTML::TreeBuilder;

    $tree->parse($html);

    return $tree;
}

sub get_page_list{
    my $html        = shift;
    my $page_mark   = shift;
    my $pages       = shift;

    my $tree = new HTML::TreeBuilder;
    $tree->parse($html);
    my @nodes = $tree->look_down( class => $page_mark );
    Carp::croak('not find page_make :'.$page_mark ) unless scalar(@nodes);
    # ul of class = 'pagebar'
    # get the last page
    my @list = $nodes[0]->content_list();
    my $last_page = ( $list[$#list-1]->find_by_tag_name('a') )[FIRST_NODE]
                    ->attr( $LINK_HREF ); 
    # a needed to subs url
    # last_page 
    #	-<a class="img" onclick="return fn_turnPage(this);" href="/sort/1_15.html">末页</a>

    ( my $needed_s_url = $last_page )
        =~ s#/(sort/\d+)_(\d+)\.html#&trim_url($url_base).'/'.$1."_".'$num'.".html"#eg;
    my $total = $2;

    # save pages to pages arrayref
    @{ $pages } = map {
        ( my $temp = $needed_s_url ) =~ s/\$num/$_/; 
        $temp
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
        &get_page_list( $web,$PAGE_MARK,$pages );
    };
    if($@){
#        print Dumper $pages;
        return 0 unless scalar @$pages
    }
    return 1;
}

sub get_app_list{
    my $html      = shift;
    my $app_mark  = shift;
    my $apps_href = shift;
    # <a href="/soft/7880.html">
    # <a href="/soft/8099.html">极限摩托车</a>
    #li class="name">
    if(my @links = $html=~ m{li class="name">.+?"(/soft/\d+\.html)"}sg){
       for(@links){
           if($_ =~ m/(\d+)/){
              $apps_href->{$1} = trim_url($url_base).$_;
           }
       }
       return 1;
    }

    return 0
}
=pod 
    my $tree = new HTML::TreeBuilder;
    $tree->parse($html);

    my @nodes = $tree->look_down( class => "name" );
    Carp::croak('not find apps nodes by this mark name')
        unless ( scalar(@nodes) );
    foreach my $node(@nodes){
    	my @a = $node->find_by_tag_name('a');
        next unless @a;
        my $app_url = $a[0]->attr('href');
        $app_url =~ m/(\d+)/;
        $apps_href->{$1} = trim_url($url_base).$app_url;
    }

    use Data::Dumper;
    print Dumper $apps_href;
    $tree->delete;
=cut

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
    # create a html tree and parse
    #my $tree = init_html_parser( $params->{web_page} );
    # exact app 
    return 0 if ref($params) ne 'HASH';
    return 0 unless exists $params->{web_page};
    eval{
    	my $html = $params->{web_page};
        get_app_list( $html,$APPS_MARK,$apps );
    };
    if($@){
        warn('extract_app_from_feeder failed'.$@);
        $apps = {};
	return 0
    }
    return 0 unless scalar( %{ $apps } );
	
    return 1;
}

sub get_author{
    my $html = shift;

    #if($html =~ m/软件作者(.*?)(\S+)/s){
    if($html =~ m/软件作者(.*?)<\/strong>(.*?)(\w+)/s){
        return $3;
    }
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
    my @nodes = $tree->look_down( class => 'brief' );
    return unless @nodes;

    my $title = [ $tree->find_by_attribute( class => 'title') ]->[FIRST_NODE];
    my $icon = [ $title->find_by_tag_name($IMG) ]->[FIRST_NODE]->attr($SRC);

    # delete what I have done
    $tree->delete;
    return $icon || undef;
}

sub get_app_name{
    my $html = shift;
    my $web  = shift;
    my $mark = shift||'qnav';
    
    my $tree = new HTML::TreeBuilder;
    $tree->parse($html);

    # find app name for app_info
    # html_string:
    # mark class = "qnav"
=pod
    <div class="qnav">
    <li>
    <li>
    <li>
    <li>拉蜂文件管理器</li>
    </div>
=cut
    my @nodes = $tree->look_down( class => 'qnav' );
    return unless @nodes;
    my @list = $nodes[0]->find_by_tag_name('li');
    # app name is li=>[3]
    my $app_name = $list[3]->as_text;

    # delete what I ever done
    $tree->delete;
    return $app_name || undef;
}

sub get_price{ 
    return 0;
}

sub get_description{
    my $html = shift;
    my $mark = shift;

    # find app description
    # match for chinese description
    # <div class="clear">
    #if( $html =~ m/应用介绍:(.*?)<div class="clear">/s ){
    # \u7cfb\u7edf\u5e94\u7528
    if( $html =~ m/(应用介绍.*?)<div/s ){
        #( my $desc = $1 ) = ~ s/[\000-\037]//g;
        my $desc = $1;
        $desc =~ s/<h\d+>//g;
        $desc =~ s/<\/h\d+>//g;
        $desc =~ s/<br>//g;
        $desc =~ s/<\/br>//g;
        $desc =~ s/<br\s+\/>/\n/g;
        $desc =~ s/\r//g;
        $desc =~ s/\n//g;
        return $desc;
    }

    return undef 
}

sub get_size{
    my $html = shift;
    # mark is class => 'info'
    my $mark = shift||'info';

    # find app size and app info l-list
    # in this market,size is in list[2]
    my $tree = new HTML::TreeBuilder;
    $tree->parse($html);
    my @nodes = $tree->look_down( class => $mark );
    my @list = $nodes[0]->content_list();
    my $size = kb_m( $list[2]->as_text );

    $tree->delete;

    return $size || undef;
}

sub get_total_install_times{
    my $html = shift;
    # mark is class => 'info'

    if( $html =~ m/下载次数(.*?)(\d+)/s ){
        my $install_times = $2;
        return $install_times;
    }

    return undef;
}

sub get_last_update{
    my $html = shift;
    # mark is class => 'info'
    # <li>
    # <strong>更新时间：</strong>
    # 2011-08-29
    if( $html=~ m/更新时间(.*?)(\d{4}-\d{2}-\d{2})/s ){
        my $time_stamp = $2;
        return $time_stamp;
    }
    return undef;
}

sub get_apk_url{
    my $html = shift;
    my $mark = shift||'down';

    # find apk_url by html_tree
    # TODO define a global var for apk_url mark class => "down"
    # html content:
=pod
<div class="down">
	<img src="/qrcode/17876.jpg">
	<br>
	<a href="/qr.html" target="_blank">二维码下载说明</a>
	<p>
		<a href="/download/17876">
		<img src="/images/download.png">
		</a>
	</p>
</div>
=cut
    my $tree = new HTML::TreeBuilder;
    $tree->parse($html);

    my @nodes = $tree->look_down( class => $mark );
    my @p = $nodes[0]->find_by_tag_name('p');
    my $url = $url_base.$p[0]->find_by_tag_name($LINK_TAG)->attr($LINK_HREF);

    $tree->delete;
    return $url || undef;
}

sub get_official_rating_stars{
    my $html  = shift;
    # find stars for app
    # html_string:
=pod
<div class="brief">
<div class="down">
<ul class="title">
<p class="icon">
<li class="h1">拉蜂文件管理器</li>
<li>
<i class="df-star star-4"></i>
</li>
</ul>
=cut
    # here, star and match by regular expression
    if( $html =~ m/df-star star-(\d+)/s ){
        return $1;
    }

    return undef;
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
    my $web  = shift;
    my $mark = 'qnav';

    my $tree = new HTML::TreeBuilder;
    $tree->parse($html);

    my @nodes = $tree->look_down( class => $mark );
    return 0 unless @nodes;

    # fetch category_id and official_category 
    # official_category li->2
    my @list = $nodes[0]->find_by_tag_name('li');
    my $official_category = ( $list[2]->find_by_tag_name($LINK_TAG) )[0]->as_text;
    $tree->delete;

    return $official_category||undef;
}

#-------------------------------------------------------------
=head
 app_info:
	-author
	-app_url
	-app_name
	-icon
	-price
	-system_requirement
	-min_os_version
	-max_os_version
	-resolution
	-last_update
	-size
	-official_rating_stars
	-official_rating_times
	-app_qr
	-note
	-apk_url
	-total_install_times
	-official_rating_times
	-description
	-official_category
	-trustgo_category_id
	-related_app
	-creenshot
	-permission
	-status
 app_feeder
	category_id
=cut

sub get_current_version{
    my $html = shift;
    my $web  = shift;
    # mark is class => 'info'
    my $mark = shift||'info';

    # find app install time and app info l-list
    # in this market,install time is in list[4]
    my $tree = new HTML::TreeBuilder;
    $tree->parse($html);
    my @nodes = $tree->look_down( class => $mark );

    my @list = $nodes[0]->find_by_tag_name('li');
    my $version_s = $list[1]->as_text ;
    #print $version_s;
    $version_s =~ m/软件版本(.*?)([0-9\.]+)/s;
    $tree->delete;
    return $2||'unknow';
}

sub get_app_qr{
    my $html = shift;
    my $mark = shift||'down';

    # html sinppet
=pod
<div class="down">
	<img src="/qrcode/17876.jpg">
<br>
=cut
    my $tree = new HTML::TreeBuilder;
    $tree->parse($html);
    my @nodes = $tree->look_down( class => 'down' );
    return 0 unless @nodes;

    # fetch img from this snippet
    my $img = ( $nodes[0]->find_by_tag_name($IMG) )[0]->attr($SRC);
    $tree->delete;

    return trim_url($url_base).$img || undef;
}
sub get_screenshot{
    my $html = shift;
    my $mark = shift||'screen-div';

    # screenshot is 'screen-div'
    # fetch src
    # html_string
=pod
<div id="screen-div" style="visibility: visible; overflow: hidden; position: relative; z-index: 2; left: 15px; width: 606px;">
<ul style="margin: 0pt; padding: 0pt; position: relative; list-style-type: none; z-index: 1; width: 1818px; left: -606px;">
	<li style="overflow: hidden; float: left; width: 170px; height: 170px;">
		<a href="http://www.anfone.com/memo_image/17876/1.jpg">
			<img width="170" height="170" src="http://www.anfone.com/memo_image/17876/1.jpg">
		</a>
	</li>
	....
</div>
=cut
    my $tree = new HTML::TreeBuilder;
    $tree->parse($html);
    my @nodes = $tree->look_down( id => $mark );
    return [] unless @nodes;
    my @tags =  $nodes[0]->find_by_tag_name('a') ;

    #retrun a arrayref
    return [ map{ $_->attr($LINK_HREF) } @tags ];
}


#-------------------------------------------------------------
sub get_permission{
    my $html = shift;
    my $mark = shift||'row';

    # the list needed to return 
    my $permission = [];
    my $tree = new HTML::TreeBuilder;
    $tree->parse($html);

    # find permission
    my @nodes = $tree->look_down( class => $mark );
    return [] unless @nodes;

    # foreach @nodes;
    # mark class => 'row' <h3>|<h4>
    # html example:
=pod
<div class="normal" style="display: block;">
	<div class="row">
		<h4>系统工具</h4>
		<p> 显示系统级警报 , 防止手机休眠 </p>
	</div>
</div>
=cut
    for( @nodes ){
        my @h3 = $_->find_by_tag_name('h3');
        my @h4 = $_->find_by_tag_name('h4');
        if( @h3 ){
          push @{ $permission },$h3[0]->as_text;
        }
        if( @h4 ){
          push @{ $permission },$h4[0]->as_text;
        }
    }

    return $permission;
}

sub get_related_app{
    my $html = shift;
    
    # a related apps 
    my $related_apps = [];
    # create a empty html tree
    my $tree = new HTML::TreeBuilder;
    $tree->parse($html);

    my @nodes = $tree->look_down( class => 'sort-r' );
    return [] unless @nodes;
    # related_apps 
    #my @re_apps_a = find_by_tag_name('a');
=pod
<div class="column-r">
	<h2>猜你喜欢</h2>
	<ul class="sort-r">
		<li>
			<a href="/soft/19120.html">
		</li>
	</ur>
</div>
=cut
	foreach my $class ( @nodes ){
		my @links = $class->find_by_tag_name('a');
		next unless @links;
		foreach my $link(@links){
			next unless ref($link);
			push @{ $related_apps },
	            trim_url($url_base).$link->attr('href');
		}
		
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
#    use Encode;
#    $html = Encode::decode_utf8($html);

    eval{
        # TODO get note 'not find'
        {
            no strict 'refs';
            foreach my $meta( @app_info_list ){
                # dymic function invoke
                # 'get_author' => sub get_author
                # 'get_price'  => sub get_price
                my $ret = $app_info->{$meta} = &{ __PACKAGE__."::get_".$meta }($html) ;
                if( defined($ret) ){
                    $app_info->{$meta} = $ret;
                }
                next;
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

sub run{
    use LWP::Simple;
    my $content = get('http://www.anfone.com/soft/19389.html');
=pod
    my $worker	 = shift;
    my $hook	 = shift;
    my $html     = shift;
    my $app_info = shift;
=cut
    my $app_info = {};
    extract_app_info( undef,undef,$content,$app_info );

}

1;
__END__



