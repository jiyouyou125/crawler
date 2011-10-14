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

my $market   = "m.1mobile.com";
my $url_base = "http://m.brothersoft.com";

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

my $dbh        = new AMMS::DBHelper;
my $cookie_jar = HTTP::Cookies->new;
$cookie_jar->set_cookie( undef, "sub_device", "2285", "/", "m.brothersoft.com",80 );

{

    package MyAppFind;
    use base 'AMMS::AppFinder';

    sub get_app_url {
        my $self           = shift;
        my $feeder_id_urls = shift;

        my $downloader = $self->{'DOWNLOADER'};
        my $logger     = $self->{'CONFIG_HANDLE'}->getAttribute('LOGGER');
        my $result     = {};
        my %params;
        foreach my $id ( keys %{$feeder_id_urls} ) {
            my @pages;

            $result->{$id}->{'status'} = 'fail';
            $downloader->timeout(
                $self->{'CONFIG_HANDLE'}->getAttribute("WebpageDownloadMaxTime")
            );
            my $web_page = $downloader->download( $feeder_id_urls->{$id} );
            if ( not $downloader->is_success ) {
                $result->{$id}->{'status'} = 'invalid'
                  if $downloader->is_not_found;
                $logger->error( 'fail to download webpage '
                      . $feeder_id_urls->{$id}
                      . ',reason:'
                      . $downloader->error_str );
                warn(   'fail to download webpage '
                      . $feeder_id_urls->{$id}
                      . ',reason:'
                      . $downloader->error_str );
                next;
            }

            utf8::decode($web_page);
            $params{'web_page'} = $web_page;
            $params{'base_url'} = $feeder_id_urls->{$id};
            my $page = $params{'base_url'};
          LOOP: {
                my %apps;
                my $webpage;
              FEED: {
                    $webpage= $downloader->download($page);
                    if ( not $downloader->is_success ) {
                        if ( $downloader->is_not_found ) {
                            $self->{'DB_HELPER'}
                              ->save_url_from_feeder( $id, $page, 'invalid' );
                        }
                        else {
                            $self->{'DB_HELPER'}
                              ->save_url_from_feeder( $id, $page, 'fail' );
                        }
                        $page =~ s/(.*)(?<=\D)(\d+)(\/)/$1.($2+1).$3/e;
                        redo FEED;
                    }
                }
                unless ( utf8::decode($webpage) ) {
                    $logger->error("fail to utf8 convert");
                }
                $params{'web_page'} = $webpage;
                $params{'base_url'} = $page;
                $self->invoke_hook_functions( 'extract_app_from_feeder',
                    \%params, \%apps );
                $self->{'DB_HELPER'}
                  ->save_app_into_source( $id, $self->{'MARKET'}, \%apps );
                $self->{'DB_HELPER'}
                  ->save_url_from_feeder( $id, $page, 'success' );

                $params{'next_page_url'} = undef;
                $self->invoke_hook_functions( 'extract_page_list', \%params,
                    \@pages );
                $page = $params{'next_page_url'};
                last LOOP if not defined($page);
                redo LOOP;
            }
            $result->{$id}->{'status'} = 'success';
        }

        $self->{'RESULT'} = $result;
        return 1;
    }

    1;
}
if ( $task_type eq 'find_app' )    ##find new android app
{

    my $AppFinder =
      new MyAppFind( 'MARKET' => $market, 'TASK_TYPE' => $task_type );
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

        #category
        my $category = $tree->look_down( class => "p_a bussines_n" );
        my @a_nodes = $category->find_by_tag_name("a");
        $app_info->{official_category} = $a_nodes[$#a_nodes]->as_text;
        if ( defined $category_mapping{ $app_info->{official_category} } ) {
            $app_info->{trustgo_category_id} =
              $category_mapping{ $app_info->{official_category} };
        }
        else {
            &save_out_of_category( $app_info->{app_url_md5} );
        }

        #app_name current_version price total_install_times size icon
        my $dbh        = new AMMS::DBHelper;
        my $extra_info = $dbh->get_extra_info( $app_info->{app_url_md5} );
        if ( ref $extra_info eq "HASH" ) {
            foreach my $item (qw/price app_name current_version icon/) {
                if ( defined( $extra_info->{$item} ) ) {
                    $app_info->{$item} = $extra_info->{$item};
                }
            }
        }

        #size
        if ( $webpage =~ /File size:([^<]+)</ ) {
            $app_info->{size} = kb_m($1);
        }

        #description
        if ( $webpage =~ /<div class="description">.*?<p>(.*?)<\/p>/s ) {
            $app_info->{description} = $1;
        }

        #last_update author total_install_times
        if ( $webpage =~
            m{Updated:</strong>([^<]+)<br/>.*?Publisher:</strong>([^<]+)<br/>.*?Downloads:</strong>(.*?)<span>}s
          )
        {
            $app_info->{last_update}         = &process_to_last_update(trim($1));
            $app_info->{author}              = trim($2);
            $app_info->{total_install_times} = trim($3);
            $app_info->{total_install_times} =~ s/,//g; 
        }

        #screenshot
        $app_info->{screenshot} = [];

        #apk_url
        if ( $webpage =~ /value="(.*?\.apk)"/) {
            $app_info->{apk_url} = $1;
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
        if ( $webpage =~
            /<div class="page">.*?<a href="([^"]+)">Next.+?<\/div>/s )
        {
            $params->{next_page_url} = $url_base . $1;
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
        my $tree    = HTML::TreeBuilder->new;
        $tree->no_expand_entities(1);
        $tree->parse($webpage);
        my $content = $tree->look_down( class => "content" );
        my @div_nodes =
          $content->look_down( "_tag", "div", "class", "aps p_a" );
        for my $node (@div_nodes) {
            next if $node->as_HTML !~ /Size:/;
            my $span  = $node->find_by_tag_name("span");
            my $price = 0;
            $price = 0 if $span->as_text =~ /Free/;
            my $dt = $node->find_by_tag_name("dt");
            my $app_name_version = trim($dt->as_text);
            my ( $app_name, $current_version ) =
              ( $app_name_version =~ /(.*)(?<= )([avV]?[.\d]+)/ );
            if(not defined($current_version)){
                $app_name = $app_name_version;
                $current_version = 0;
            }
            my $a = $node->look_down( "_tag", "a" );
            my $app_url = encode_utf8($url_base . $a->attr("href"));
            $apps->{$1} = $app_url
              if $a->attr("href") =~ /.*(?<!\d)(\d+)\/$/;
            my $image_node = $node->find_by_tag_name("img");
            $dbh->save_extra_info(
                md5_hex($app_url),
                {
                    price           => $price,
                    app_name        => trim($app_name),
                    current_version => trim($current_version),
                    icon            => $image_node->attr("src"),
                }
            );
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
    $date =~ s/(\w+) (\d+),(\d{4})/$3-$month{$1}-$2/;
    return $date;
}
