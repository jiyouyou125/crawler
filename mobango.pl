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
use File::Spec;
use JSON;

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

my $market   = "www.mobango.com";
my $url_base = "http://www.mobango.com";

my $downloader = new AMMS::Downloader;

my %category_mapping = (
    'Action'           => 823,
    'Adventure'        => 800,
    'Arcade'           => 801,
    'Board'            => 802,
    'Card'             => 803,
    'Casino'           => 804,
    'Fun'              => 8,
    'Mobile'           => 8,
    'Others'           => 8,
    'Puzzle'           => 810,
    'Sports'           => 814,
    'Strategy'         => 815,
    'Audio'            => 7,
    'Browser'          => 2210,
    'Business'         => 2,
    'Education'        => 5,
    'Entertainment'    => 7,
    'Finance'          => 2,
    'Photo'            => 15,
    'Lifestyle'        => 19,
    'Messenger/Chat'   => 400,
    'Mobile'           => 22,
    'Navigation'       => 821,
    'News/Information' => 14,
    'Others'           => 22,
    'Productivity'     => 16,
    'SMS'              => 4,
    'Social & Community' => 18,
    'Sports'           => 20,
    'Customization'    => 12,
    'Travel'           => 21,
    'Utility'          => 22,
    'Video'            => 707,
);

die "\nplease check config parameter\n" unless init_gloabl_variable($conf_file);

my $dbh        = new AMMS::DBHelper;
my $cookie_jar = HTTP::Cookies->new;
my $ua         = LWP::UserAgent->new;

$ua->cookie_jar($cookie_jar);
$ua->get("http://www.mobango.com");
my $res = $ua->post(
    'http://www.mobango.com/handler/HandsetSelectorHandler.php',
    [
        'valueMobile' => 'Google Nexus One HTC Nexus One Google Phone',
        'wurflId'     => 'google_nexusone_ver1_sub22',
    ]
);

if ( $res->is_success ) {
}

if ( $task_type eq 'find_app' )    ##find new android app
{

    my $AppFinder =
      new AMMS::AppFinder( 'MARKET' => $market, 'TASK_TYPE' => $task_type );
    $AppFinder->{DOWNLOADER}->{USERAGENT}->cookie_jar($cookie_jar);
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
    $NewAppExtractor->{DOWNLOADER}->{USERAGENT}->cookie_jar($cookie_jar);
    $NewAppExtractor->addHook( 'extract_app_info', \&extract_app_info );
    $NewAppExtractor->run($task_id);
}
elsif ( $task_type eq 'update_app' )    ##download updated app info and apk
{
    my $UpdatedAppExtractor = new AMMS::UpdatedAppExtractor(
        'MARKET'    => $market,
        'TASK_TYPE' => $task_type
    );
    $UpdatedAppExtractor->{DOWNLOADER}->{USERAGENT}->cookie_jar($cookie_jar);
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

        #icon
        my $dbh        = new AMMS::DBHelper;
        my $extra_info = $dbh->get_extra_info( $app_info->{app_url_md5} );
        if ( ref $extra_info eq "HASH" ) {
            foreach my $item (qw/icon/) {
                if ( defined( $extra_info->{$item} ) ) {
                    $app_info->{$item} = $extra_info->{$item};
                }
            }
        }

        #app_name
        if ( $webpage =~ /Download (.*?) for your phone/ ) {
            $app_info->{app_name} = $1;
        }

        #price
        $app_info->{price} = 0;

        #description
        my $description_tab =
          $tree->look_down( id => 'tabShortLanguageContent' );
        my $en_desc = $description_tab->look_down( id => 'en' );

        $app_info->{description} = $en_desc->as_text if ref $en_desc;
        if ( not defined( $app_info->{description} ) ) {
            my $des = $tree->look_down( id => "softwareDetailDescription" );
            $app_info->{description} = $des->as_text;
        }

        #official_rating_stars official_rating_times
        if ( $webpage =~ /MobangoRating\('[^']+', '([^']+)'/ ) {
            $app_info->{official_rating_stars} = $1;
        }
        ( $app_info->{official_rating_times} ) =
          ( $webpage =~ /<div class="rating_votes">.*?(\d+) votes.*?<\/div>/s );

#last_update author total_install_times copyright category release_date current_version
        my $info_list = $tree->look_down( id => "info-list-details" );
        my $info_list_text = $info_list->as_text;
        if ( $info_list_text =~
m{Uploaded: (.*?)Updated: (.*?)Version: (.*?)Downloads: (\d+)Category: (.*?)Views: (\d+)License: (.*?) (?:Company Name|Developer:)(.*)}s
          )
        {
            my %matched = (
                uploaded            => $1,
                last_update         => $2,
                current_version     => $3,
                total_install_times => $4,
                official_category   => $5,
                copyright           => $7,
                author              => trim($8),
            );
            $app_info->{last_update} =
              &process_to_last_update( $matched{last_update} );
            $app_info->{current_version} = $matched{current_version} || 0;
            $app_info->{release_date} =
              &process_to_last_update( $matched{uploaded} );
            $app_info->{total_install_times} = $matched{total_install_times};
            $app_info->{official_category}   = $matched{official_category};
            $app_info->{author}              = $matched{author};
            if (
                defined(
                    $category_mapping{ ucfirst $app_info->{official_category} }
                )
              )
            {
                $app_info->{trustgo_category_id} =
                  $category_mapping{ ucfirst $app_info->{official_category} };
            }
            else {
                &save_out_of_category( $app_info->{app_url_md5} );
            }
        }

        #screenshot
        my $downloader = new AMMS::Downloader;
        $downloader->{USERAGENT}->cookie_jar($cookie_jar);
        my @screen_nodes = ( $webpage =~ /setScreenshot\((\d+)\)/g );
        my ($PHPSESSION) = ( $cookie_jar->as_string =~ /PHPSESSID=([^;]+);/ );
        foreach (@screen_nodes) {
            my $request_url = $url_base
              . "/swarea/index.php?json=screenshot_url_by_id_image&idImage=";
            $request_url .= $_ . "&cookie=" . $PHPSESSION;
            my $content = $downloader->download($request_url);
            if ( $downloader->is_success ) {
                my $json = eval{ decode_json(decode_utf8($content))};
                if(not $@){
                    push @{ $app_info->{screenshot} }, $json->{imageUrl};
                }
            }
        }

        #apk_url size
        if ( $webpage =~ /<a href="([^"]+)">Download APK.*?(?:Size: ([^)]+))?\)/s ) {
            $app_info->{apk_url} = $url_base . $1;
            $app_info->{size}    = kb_m($2) || 0;
        }

        #comment_times
        my @comment_nodes = $tree->look_down( class => 'comments-review-box' );
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
        push @$pages, $params->{'base_url'};
        if ( decode_entities($webpage) =~
            m{.*<li class="next"[^>]*>[^<]*<a href="([^"]+)">}s )
        {

            my $url_template = $1;
            $total_pages = $1 if $url_template =~ s/pageNum=(\d+)&//;
            for ( 2 .. $total_pages ) {
                push @$pages, $url_base . $url_template . "&pageNum=" . $_;
            }
        }
    };

    return 1;
}

sub extract_app_from_feeder {
    my $tree;
    my @node;

    my ( $worker, $hook, $params, $apps ) = @_;

    eval {
        my $webpage = decode_entities( $params->{'web_page'} );
        my @apps =
          ( $webpage =~
m{<div class="thumbnail">[^<]+<a href="([^"]+)">[^<]+<img.*?src="([^"]+)"}g
          );
        my %app_info = @apps;

        while ( my ( $app_url, $icon ) = each(%app_info) ) {
            my $app_url_real = encode_utf8( $url_base . $app_url );
            $app_url_real =~ s/&listNum=\d+//;
            $app_url_real =~ s/&title=[^&]+//;
            $apps->{$1} = $app_url_real if $app_url =~ /idsw_mobango=(\d+)&/;
            $dbh->save_extra_info( md5_hex($app_url_real), { icon => $icon } );
        }
    };
    $apps = {} if $@;

    return 1;
}

sub save_out_of_category {
    my ($app_url_md5) = @_;
    my $str = "Out of TrustGo category:" . $app_url_md5;
    open( OUT, ">>/home/nightlord/outofcat.txt" );
    print OUT "$str\n";
    close(OUT);
    die "Out of Category";
    return;
}

sub kb_m {
    my $size = shift;
    return undef if not defined($size);
    # MB -> KB
    $size = $1 * 1024 if ( $size =~ s/([\d\.]+)(.*MB.*)/$1/i );
    $size = $1        if ( $size =~ s/([\d\.]+)(.*KB.*)/$1/i );

    #             # return byte
    return int( $size * 1024 );
}

sub process_to_last_update {
    my $date  = shift;
    my %month = (
        Jan => '01',
        Feb => '02',
        Mar => '03',
        Apr => '04',
        May => '05',
        Jun => '06',
        Jul => '07',
        Aug => '08',
        Sep => '09',
        Oct => '10',
        Nov => '11',
        Dec => '12',
    );
    $date =~ s/(\w+) (\d+),\s*(\d{4})/$3-$month{$1}-$2/;
    return $date;
}
