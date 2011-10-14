#!/usr/bin/perl
use strict;
use LWP::UserAgent;
use HTML::TreeBuilder;
use IO::Handle;
use HTTP::Cookies;
use Encode;

my $ua = LWP::UserAgent->new;
$ua->timeout(60);
$ua->env_proxy;
my $cookie_jar = HTTP::Cookies->new;
$cookie_jar->set_cookie(undef,"sub_device","2285","/","m.brothersoft.com",80); 
$ua->cookie_jar($cookie_jar);

open( FEED, ">1mobile.url" );
FEED->autoflush(1);

my $portal   = 'http://m.brothersoft.com';
my $base_url = "http://m.brothersoft.com";

my $response = $ua->get($portal);

while ( not $response->is_success ) {
    $response = $ua->get($portal);
}

if($response->is_success){
    my $webpage = $response->content;
    $webpage = decode_utf8($webpage);
    my @urls = ($webpage =~ m{<a href="([^"]+(?:1-applications|2-games)/)">.*?</a>}sg);
    foreach my $url(@urls[0,1]){
        my $res = $ua->get($base_url . $url);
        if($res->is_success){
            my $content = $res->content;
            $content = decode_utf8($content);
            my $tree = HTML::TreeBuilder->new;
            $tree->parse($content);
            my $category_area = $tree->look_down(class => "recommended_b");
            my @category_a = $category_area->look_down("_tag","a");
            foreach my $item(@category_a){
                print FEED $base_url.$item->attr("href"),"\n";
            }
            $tree->delete;
        }
    }
}

close FEED;
