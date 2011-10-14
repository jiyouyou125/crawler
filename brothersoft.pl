#!/usr/bin/perl
BEGIN { unshift( @INC, $1 ) if ( $0 =~ m/(.+)\// ); }
use strict;
use utf8;
use warnings;
use File::Basename;
use Digest::MD5 qw/md5_hex/;
use HTML::TreeBuilder;
use Encode;
use HTML::Entities;
use HTTP::Cookies;

use AMMS::Util;
use AMMS::AppFinder;
use AMMS::Downloader;
use AMMS::NewAppExtractor;
use AMMS::UpdatedAppExtractor;
use AMMS::DBHelper;
use Data::Dumper;

my $task_type = $ARGV[0];
my $task_id   = $ARGV[1];
my $conf_file = $ARGV[2];

my $market   = "www.brothersoft.com";
my $url_base = "http://www.brothersoft.com";

my $downloader = new AMMS::Downloader;

my %category_mapping = (
    'Business'           => 2,
    'Communication'      => 4,
    'Ebooks & Reference' => 1,
    'Email & SMS'        => 4,
    'Entertainment'      => 6,
    'Food & Health'      => 9,
    'GPS & Travel'       => 21,
    'Home & Education'   => 5,
    'Internet'           => 2216,
    'Mobile Dictionary'  => 103,
    'MP3 & Audio'        => 7,
    'News & Weather'     => 14,
    'Photo & Graphics'   => 15,
    'Social Networking'  => 18,
    'Utilities'          => 22,
    'Video'              => 707,
    'Action'             => 823,
    'Adventure'          => 800,
    'Card & Casino'      => "803,804",
    'Miscellaneous'      => 8,
    'Puzzle'             => 810,
    'RPG'                => 812,
    'Shooting'           => 821,
    'Sports'             => 814,
    'Strategy'           => 815,
    'Tower Defense'      => 8,
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
        $tree->no_expand_entities(1);
        $tree->parse($webpage);

        #category
        my $sub_nav = $tree->look_down( class => "subNav2" );

        if ( $sub_nav->as_HTML =~ /You are here:.*<a[^>]+>(.*?)<\/a>/g ) {
            $app_info->{official_category} = decode_entities($1);
            if (
                defined( $category_mapping{ $app_info->{official_category} } ) )
            {
                $app_info->{trustgo_category_id} =
                  $category_mapping{ $app_info->{official_category} };
            }
        }

        #app_name,version
        my $app_ver = $tree->look_down( class => "down_mid" );
        if ($app_ver) {
            my $app_ver_h2 = $app_ver->find_by_tag_name("h2");
            ( $app_info->{app_name}, $app_info->{current_version} ) =
              ( $app_ver_h2->as_text =~ /(.*)[vV]?(?<= )([\.\d]+)/ );
            if ( not defined( $app_info->{current_version} ) ) {
                $app_info->{current_version} = 0;
                $app_info->{app_name}        = trim( $app_ver_h2->as_text );
            }
            $app_info->{app_name} = trim($app_info->{app_name});
        }

        #download_last_week
        my $download_btn  = $tree->look_down( id => "downloadbut" );
        my $down_load_a   = $download_btn->find_by_tag_name("a");
        my $down_load_url = $url_base . $down_load_a->attr("href");
        my $download_html = $download_btn->as_HTML;
        if ( $download_html =~ m{Downloads of Last Week:\s*(\d+)} ) {
            $app_info->{total_install_times} = $1;
        }

        #size
        if ( $download_html =~ m{<span>(.*?)</span>} ) {
            $app_info->{size} = kb_m($1);
        }
        $app_info->{size} = 0 if not defined($app_info->{size});

        #screenshot
        my $screen_node = $tree->look_down( class => "program_r" );
        my @img = $screen_node->find_by_tag_name("img");
        push @{ $app_info->{screenshot} }, $_->attr("src") foreach @img;

        #last_update,author,price
        my $license = $tree->look_down( class => "license" );
        my $license_price =
          $license->look_down( "_tag", "div", "class", "free_p" );
        my ( $license_text, $price ) =
          ( $license_price->as_text =~ /:(.*?)\/(.*)/ );
        $app_info->{price} = 0 if $price =~ /(Free|-)/;
        $app_info->{price} = "USD:".$1  if $price =~ /\$([.\d]+)/;
        $app_info->{price} = "EUR:".$1  if $price =~ /E(?:UR)?([.\d]+)/;
        if ($price =~ /^\s*([.\d]+)\s*$/){
            my $tmp_price = $1;
            if($tmp_price =~ /^0([.0]+)?$/){
                $app_info->{price} = 0;
            }else{
                $app_info->{price} = "USD:".$tmp_price;
            }
        }
        $app_info->{copyright} = trim($license_text);

        my $license_html = $license->as_HTML;
        if ( $license_html =~ m/Last Updated:.*?(\d{4}-\d{2}-\d{2})/s ) {
            $app_info->{last_update} = $1;
        }
        if ( $license_html =~ /Publisher:.*?<a[^>]+>(.*?)<\/a>/s ) {
            $app_info->{author} = $1;
        }

        #descripton
        my $desc = $tree->look_down( class => "editor_s" );
        $app_info->{description} = $desc->as_text;

        #icon
        my $dbh        = new AMMS::DBHelper;
        my $extra_info = $dbh->get_extra_info( $app_info->{app_url_md5} );
        if ( ref $extra_info eq "HASH" ) {
            $app_info->{icon} = $extra_info->{icon}
              if defined $extra_info->{icon};
        }
        else {
            $app_info->{icon} = $app_info->{screenshot}->[0]
              if scalar $app_info->{screenshot};
        }
        

        #apk_url
        my $downloader = AMMS::Downloader->new;
        my $cookie_jar = HTTP::Cookies->new;
        $cookie_jar->set_cookie( undef, "mobile_phone_name", "HTC%20Desire",
            "/mobile/", "www.brothersoft.com", 80 );
        $cookie_jar->set_cookie( undef, "mobile_phone_url", "/htc/htc_desire",
            "/mobile/", "www.brothersoft.com", 80 );
        $cookie_jar->set_cookie( undef, "sub_device", "2015", "/", "m.brothersoft.com",80 );
        $downloader->{USERAGENT}->cookie_jar($cookie_jar);

        #icon total_install_times
        my $base_name = $1 if $app_info->{app_url} =~ /.*\/(.*?)\.html/;
        my $m_brothersoft_url = "http://m.brothersoft.com/$base_name/";
        my $brothersoft_info = $downloader->download($m_brothersoft_url);
        if($downloader->is_success){
            if($brothersoft_info =~ m{<img src="([^"]+)"[^>]+?class="thumb"/>}s){
                $app_info->{icon} = $1;
            }
            if($brothersoft_info =~ m{<strong>Downloads:</strong>.*?([\d,]+)}s){
                my $tmp_times = trim($1);
                $tmp_times =~ s/,//g;
                $app_info->{total_install_times} = $tmp_times;
            }
        }
        my $page = $downloader->download($down_load_url);
        if ( $downloader->is_success ) {

            if ( $page =~ /<a.*?href="(.*?)".*>Download Now<\/a>/ ) {
                $app_info->{apk_url} = $url_base . $1;
            }
        }
        $tree->delete;
    };
    $app_info->{status} = 'success';

    $app_info->{status} = 'fail' if $@;
    return scalar %{$app_info};
}

sub extract_page_list {

    my ( $worker, $hook, $params, $pages ) = @_;

    my $webpage     = $params->{'web_page'};
    my $total_pages = 0;
    eval {
        my $per_page;

        if ( $webpage =~ /Showing\s\d+-(\d+)\sof\s(\d+)\sResults/ ) {
            $per_page    = $1;
            $total_pages = int( $2 / $per_page + 0.99 );
        }
        push @{$pages}, $params->{base_url} . "index.html";
        for ( 2 .. $total_pages ) {
            push @{$pages}, $params->{base_url} . $_ . ".html";
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

        my $dbh = new AMMS::DBHelper;
        $tree = HTML::TreeBuilder->new;
        $tree->no_expand_entities(1);
        $tree->parse($webpage);
        my $showing_node = $tree->look_down( class => "showing" );

        my @nodes = $showing_node->look_down( "_tag", "dl", );
        for my $item (@nodes) {
            my $parent = $item->parent();
            my $img = $parent->look_down( "_tag", "img" );

            #app_url
            my $dt = $item->find_by_tag_name("dt");
            if ($dt) {
                my $app_name_ver_a_tag = $dt->find_by_tag_name("a");
                my $app_url =
                  $url_base . encode_utf8( $app_name_ver_a_tag->attr("href") );
                $apps->{$1} = $app_url
                  if $app_name_ver_a_tag->attr("href") =~ /(\d+)\.html/;
                $dbh->save_extra_info( md5_hex($app_url),
                    { icon => $img->attr("src") } );
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

