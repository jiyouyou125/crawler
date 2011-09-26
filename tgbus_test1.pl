#!/usr/bin/perl
BEGIN { unshift( @INC, $1 ) if ( $0 =~ m/(.+)\// ); }
use strict;
use utf8;
use warnings;
use Data::Dumper;
use HTML::Entities;
use URI;
use Encode;

use AMMS::Util;
use AMMS::AppFinder;
use AMMS::Downloader;
use AMMS::NewAppExtractor;
use AMMS::UpdatedAppExtractor;


my $task_type = $ARGV[0];
my $task_id   = $ARGV[1];
my $conf_file = $ARGV[2];

my $market     = 'dg.tgbus.com';
my $url_base   = 'http://dg.tgbus.com';
my $downloader = new AMMS::Downloader;

my %category_mapping = (
    "竞速游戏" => 811,
    "角色扮演" => 802,
    "动作冒险" => 823,
    "益智休闲" => 806,
    "音乐游戏" => 809,
    "手机网游" => 822,
    "射击游戏" => 821,
    "策略游戏" => 815,
    "模拟游戏" => 813,
    "桌面棋牌" => 803,
    "体育竞技" => 814,
    "其它类型" => 8,
	"PC端工具" => 22,
	"生活助理" => 19,
	"系统工具" => 22,
	"网络应用" => 4,
	"通讯管理" => 4,
	"安全防护" => 23,
	"GPS导航" => 1302,
	"阅读学习" => "1,5",
	"媒体应用" => 7,
	"财务工具" => 2,
);
=pod
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
=cut
#-------------------------------------------------------------------------------
#  app_name
#  official_category
#  trustgo_category
#  last_update
#  size
#  current_version
#  app_url
#  description
#
#  author
#  support_os
#  app_capacity
#  system_requirement
#  max_os_version
#  min_os_version
#  resolution
#  note
#  official_rating_stars
#  official_rating_times
#  release_date
#  price
#  currency
#  total_install_times
#  website
#  support_website
#  language
#  copyright
#  age_rating
#  permission
#  last_visited_time
#  first_visited_time
#  last_success_visited_time
#  last_modified_time
#  visited_times
#  updated_times
#  app_qr
#-------------------------------------------------------------------------------
sub extract_app_info {
    my $tree;
    my @nodes;
    my @tags;
    my @kids;
    my ( $worker, $hook, $webpage, $app_info ) = @_;

    eval {
        $tree = HTML::TreeBuilder->new;
        $tree->parse($webpage);

        $app_info->{author} = "巴士商店";    #未知
		#title
		my $title = $1 if $webpage =~ /<title>([^<]+)<\/title>/;
	
        @nodes = $tree->look_down( "_tag", "div", "class", "Tariff-t" );
        ( $app_info->{app_name}, $app_info->{current_version} ) =
          ( &get_app_name_version($nodes[0]->as_text))
          if scalar @nodes;
		  $app_info->{current_version} = 0 if not defined($app_info->{current_version});  
		  if(not defined($app_info->{app_name}) || not defined($app_info->{current_version})){
				die "not has app_name or current_version";
			}

        # main app info
        my $app_area =
          ( $tree->look_down( "_tag", "div", "class", "Tariff" ) )[0]->as_text;
        if ( $app_area =~
/软件性质：(.*?)软件标签：(.*?)发布时间：(.*?)格式\/大小：(.*?)软件类型：(.*?)适用系统：(.*?)上传者：(.*?)适用型号：(.*?)和/m
          )
        {
            my %matched = (
                soft_nature    => $1,
                soft_label     => $2,
                publish_date   => $3,
                format_size    => $4,
                soft_category  => $5,
                satisfy_system => $6,
                upload_author  => $7,
                satisfy_model  => $8,
            );
            $app_info->{price} = 0 if $matched{soft_nature} =~ /免费/;
            $app_info->{last_update} = $matched{publish_date};
            $app_info->{size} = $1 if $matched{format_size} =~ /^\D+(\d+).*/;
			print Dumper(\%matched);
			$app_info->{official_category} = $matched{soft_category};
			if(defined($category_mapping{ $app_info->{official_category}})){
				$app_info->{trustgo_category_id} = $category_mapping{$app_info->{official_category}};	
			}else{
				my $str = "Out of TrustGo category:".$app_info->{app_url_md5};
				open(OUT,">>/root/outofcat.txt");	
				print OUT "$str\n";
				close(OUT);
				die "Out of Category";
			}
        }

        #app_icon
        @nodes = $tree->look_down( "_tag", "a", "class", "highslide" );
        @tags = $nodes[0]->find_by_tag_name("img") if scalar @nodes;
        $app_info->{icon} = $tags[0]->attr("src") if scalar @tags;

        #apk_url
        @nodes = $tree->look_down( class => "Tariff-b2-2" );
        my @a_tag = $nodes[0]->find_by_tag_name("a");
        if ( scalar @a_tag ) {
			local $URI::ABS_REMOTE_LEADING_DOTS = 1;
            $app_info->{apk_url} =
              URI->new( $a_tag[0]->attr("href") )->abs(&get_base_url($title))->as_string;
			#app_url
			$app_info->{app_url} = &get_base_url($title) . "/item-". $1 .".html"
				if $a_tag[0]->attr("href") =~ /(\d+).html$/;
        }

        #description
        @nodes = $tree->look_down( class => "software-b1" );
        $app_info->{description} = $nodes[0]->as_text if scalar @nodes;

        #screenshot
		@tags = $tree->look_down("_tag","img",sub{ defined($_[0]->attr("onload")) && $_[0]->attr("onload") =~ /javascript/;});
        push @{ $app_info->{screenshot} }, $_->attr("src") foreach @tags;
		
        $tree->delete;
    };
	print Dumper($app_info);
    $app_info->{status} = 'success';
    $app_info->{status} = 'fail' if $@;
    return scalar %{$app_info};
}

sub extract_page_list {
	print "extract_page_list.....begin\n";
    use File::Basename;

    my $tree;
    my @nodes;
    my @tags;

    my ( $worker, $hook, $params, $pages ) = @_;

    my $total_pages = 0;

    eval {
        $tree = HTML::TreeBuilder->new;
        $tree->parse( $params->{'web_page'} );
		my $title = $1 if $params->{'web_page'} =~ /<title>([^<]+)<\/title>/;
		my $base_url_real = &get_base_url($title);
        @nodes = $tree->look_down( "_tag", "div", "class", "pic1-bb" );
        @tags = $nodes[0]->find_by_tag_name("i");
        my $page_node = ( $tags[0]->find_by_tag_name("a") )[0];
        if ( $page_node->attr("onclick") =~ /WebPages\(([^)]+)\)/ ) {
            my $content = $1;
			print $content,"\n";
            $content =~ s/','/_/g;
			print $content,"\n";
			$content =~ s/'//g;
			print $content,"\n";
            my ( $pre, $mid, $post ) = split /_/, $content;
            return 0 if $post eq "0";
            push @$pages,
              map { $base_url_real ."/". $pre . $mid . "-" . $_ . ".html" } 1 .. $post;
        }
		print Dumper($pages);
    };
    return 1;
}

sub extract_app_from_feeder {
	print "extract_app_from_feeder begin.............\n";
    my $tree;
    my @node;

    my ( $worker, $hook, $params, $apps ) = @_;

    eval {
        $tree = HTML::TreeBuilder->new;    # empty tree
        $tree->parse( $params->{'web_page'} );
		
		my $title = $1 if $params->{'web_page'} =~ /<title>([^<]+)<\/title>/;
		my $base_url_real = &get_base_url($title);
        @node = $tree->look_down( class  => "EBook" );
        my @a_tag = $node[0]->look_down("_tag","a",sub{$_[0]->attr("href") =~ /item-\d+/;});
        foreach my $item (@a_tag) {
			next if not ref $item;
            $apps->{$1} =  $base_url_real ."/". $item->attr("href")
              if  scalar(@a_tag) && $item->attr("href") =~ /item-(\d+)/;
        }
=pod
		my @dl_tags = $node[0]->find_by_tag_name("_tag","dl");
		foreach my $item(@dl_tags){
			my $content = decode_entities($item->as_HTML);					
			print $content;
			my($app_url,$app_id,$platform) = ($content =~/(item-(\d+)\.html).*?search-size[^>]+>([^<]+)<\/a>/sm);
			if(defined($platform) && ($platform eq "Android")){
				$apps->{$app_id} = $base_url_real . "/" .$app_url;	
			}
		}
=cut
        $tree = $tree->delete;
    };
    $apps = {} if $@;

    return 1;
}
sub get_base_url {
	my($page_title)	= @_;
	if($page_title =~ /手机游戏/m){
		return $url_base."/game";
	}else{
		return $url_base."/soft";
	}	
} ## --- end sub get_base_url
#-------------------------------------------------------------------------------
#  get app_name and version
#  version may none
#-------------------------------------------------------------------------------
sub get_app_name_version{
	my $content = shift;
	my $app_name;
	my $current_version;
	if($content =~ /\./){
		($app_name,$current_version) = ($content =~/(.*?)[vV]?((?:\d\.)+\d)/);	
	}else{
		$app_name = $content;
	}
	$app_name = rtrim($app_name);
	return ($app_name,$current_version);
}
