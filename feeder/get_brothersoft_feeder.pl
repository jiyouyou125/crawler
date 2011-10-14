#!/usr/bin/perl
use strict;
use LWP::UserAgent;
use HTML::TreeBuilder;
use IO::Handle;

my $ua = LWP::UserAgent->new;
$ua->timeout(60);
$ua->env_proxy;

open( FEED, ">brothersoft.url" );
FEED->autoflush(1);

my $portal   = 'http://www.brothersoft.com/mobile/android/';
my $base_url = "http://www.brothersoft.com";

my $response = $ua->get($portal);

while ( not $response->is_success ) {
    $response = $ua->get($portal);
}

if ( $response->is_success ) {
    my $tree;
    my @node;
    my @li_kids;

    my $webpage = $response->content;
    eval {
        $tree = HTML::TreeBuilder->new;    # empty tree
        $tree->parse($webpage);

        @node = $tree->look_down( class => 'categories_con' );
        my @a_tags = $node[0]->look_down(
            "_tag", "a",
            sub {
                ( $_[0]->parent()->tag() ne "dt" )
                  && ( $_[0]->attr("href") !~ /wallpaper/
            );
            } );
        foreach (@a_tags) {
              my $url = $base_url . $_->attr("href");
              print $url, "\n";
              print FEED "$url\n";
        }
    };
    if ($@) {
          die "fail to extract Hiapk feeder url";
    }
}
close(FEED);
