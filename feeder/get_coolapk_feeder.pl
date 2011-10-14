#!/usr/bin/perl
use strict;
use LWP::UserAgent;
use HTML::TreeBuilder;
use IO::Handle;
use Carp;
    
my $ua = LWP::UserAgent->new;
$ua->timeout(60);
$ua->env_proxy;

open(FEED,">coolapk.url");
FEED->autoflush(1);

my $apps_portal='http://www.coolapk.com/apk/';
my $base_url = 'http://www.coolapk.com';

foreach my $portal ( $apps_portal  ){
    my $response = $ua->get($portal);
    while( not $response->is_success){
        $response=$ua->get($portal);
    }
                                         
    if ($response->is_success) {
        my $tree;
        my @node;
        my @li_kids;

        my $webpage=$response->content;
        eval {
            $tree = HTML::TreeBuilder->new; # empty tree
            $tree->parse($webpage);
            #<div id="leftbar" class="leftfilter">
            @node = $tree->look_down( id => 'leftbar' );
            Carp::croak( "not find this mark leftbar" ) unless @node;   
            my @tags = $node[0]->find_by_tag_name('a');
            Carp::croak( "not find thi mark a link" ) unless @tags;
            for(@tags){
                my $link = $_->attr('href');
                if($link =~ m/game/ ){
                    print FEED $base_url.$link."\n";
                }
                if($link =~ m/apk/ ){
                    print FEED $base_url.$link."\n";
                }
            }
        };
        if($@){
            die "fail to extract Hiapk feeder url: $@";
        }
    }
}
close(FEED);

