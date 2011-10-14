#!/usr/bin/perl 
use strict;
use warnings;
use utf8;

use HTTP::Cookies;
use HTML::TreeBuilder;
use Encode;
use Digest::MD5 qw/md5_hex/;

use AMMS::DBHelper;
use AMMS::Downloader;
use AMMS::Util;

my $market     = "m.1mobile.com";
my $url_base   = "http://m.1mobile.com";
my $dbh        = new AMMS::DBHelper;
my $market_id  = &get_market_id;
my $downloader = new AMMS::Downloader;
my $cookie_jar = HTTP::Cookies->new;
$cookie_jar->set_cookie( undef, "sub_device", "2285", "/", "m.1mobile.com",
    80 );
$downloader->{USERAGENT}->cookie_jar($cookie_jar);

my $feeder_urls = &get_feeder_urls;
foreach my $feeder_id ( keys %$feeder_urls ) {
    my $webpage = $downloader->download( $feeder_urls->{$feeder_id} );
    if ( $webpage =~
        /<div class="page">.*?<a href="([^"]+)">.*?<\/a>.*?<\/div>/s )
    {
        my $first_page = $1;
        my ( $page_base, $next_page_num ) = ( $first_page =~ m{(.*/)(\d+)/} );
      LOOP: {
            my $feed_url = $url_base . $page_base . $next_page_num;
            my $content  = $downloader->download($feed_url);
            if ( $downloader->is_success ) {
                my $status = &save_feeder_info( $feeder_id, $feed_url, "undo" );
                if ($status) {
                    &process_app_info_by_feed_info( $feeder_id, $content, $feed_url );
                }
                $next_page_num++;
                next LOOP;
            }
        }
    }
}

sub get_feeder_urls {
    my $sql = "select feeder_id,feeder_url from feeder where market_id = ?";
    my $sth = $dbh->{DB_Handle}->prepare($sql);
    $sth->execute($market_id);
    my $feeder = {};
    while ( my $row = $sth->fetchrow_hashref ) {
        $feeder->{ $row->{feeder_id} } = $row->{feeder_url};
    }
    return $feeder;
}

sub save_app_source {
    my $feeder_id = shift;
    my $apps      = shift;
    my $sql =
"replace into app_source set feeder_id=?,app_url_md5 =?,app_url =?,app_self_id=?,market_id=?,status=?,last_visited_time=NOW()";
    my $sth = $dbh->{DB_Handle}->prepare($sql);
    while ( my ( $self_id, $app_url ) = each(%$apps) ) {
        $sth->execute( $feeder_id, md5_hex($app_url), $app_url, $self_id,
            $market_id, "undo" );
    }
}

sub process_app_info_by_feed_info {
    my $feeder_id = shift;
    my $webpage   = shift;
    my $feeder_url = shift;
    my $apps      = {};
    my $tree      = HTML::TreeBuilder->new;
    $tree->no_expand_entities(1);
    $tree->parse($webpage);
    my $content = $tree->look_down( class => "content" );
    my @div_nodes = $content->look_down("_tag","div","class","aps p_a");
    for my $node (@div_nodes) {
        next if $node->as_HTML !~ /Size:/;
        my $span = $node->find_by_tag_name("span");
        my $price = 0;
        $price = 0 if $span->as_text =~ /Free/;
        my $dt = $node->find_by_tag_name("dt");
        #my ( $file_size, $total_install_times ) = ( $node->as_HTML =~
        #      m{Size:</strong>(.*?)<strong>Downloads:</strong>([^>]+)<}s );
        #$total_install_times =~ s/,//g;
        my ( $app_name, $current_version ) =
          ( $dt->as_text =~ /(.*?)[vV]?((?<=\W)(?:[.\d]\s?)+).*$/ );
        my $a = $node->look_down( "_tag", "a" );
        my $app_url = $url_base . $a->attr("href");
        $apps->{$1} = $app_url
          if $a->attr("href") =~ /.*(?<!\d)(\d+)\/$/;
        my $image_node = $node->find_by_tag_name("img");
        eval{
        $dbh->save_extra_info(
            md5_hex($app_url),
            {
                price               => $price,
                app_name            => $app_name,
                current_version     => $current_version,
                icon                => $image_node->attr("src"),
                feeder_url             => $feeder_url,
            }
        );
    };
    if($@){
        print $@,"\n";
    }
    }
    $tree->delete;
    &save_app_source( $feeder_id, $apps );
}

sub save_feeder_info {
    my $feeder_id = shift;
    my $feed_url  = shift;
    my $status    = shift;
    eval {
        my $sql =
"replace into feed_info set feeder_id=?, feed_url_md5=?,feed_url=?,status=?,last_visited_time=NOW()";
        my $sth = $dbh->{DB_Handle}->prepare($sql);
        $sth->execute( $feeder_id, md5_hex($feed_url), $feed_url, $status );
    };
}

sub get_feeder_id {
    my $feeder_url = shift;
    my $row =
      $dbh->{DB_Handle}
      ->selectrow_hashref( "select feeder_id from feeder where feeder_url = ?",
        undef, $feeder_url );
    if ($row) {
        return $row->{feeder_id};
    }
    return undef;
}

sub get_market_id {
    my $row =
      $dbh->{DB_Handle}
      ->selectrow_hashref( "select id from market where name=?",
        undef, $market )
      or die $dbh->errstr;
    return $row->{id};
}

sub kb_m {
    my $size = shift;

    # MB -> KB
    $size = $1 * 1024 if ( $size =~ s/([\d\.]+)(.*MB.*)/$1/i );
    $size = $1        if ( $size =~ s/([\d\.]+)(.*KB.*)/$1/i );

    # return byte
    return int( $size * 1024 );
}
