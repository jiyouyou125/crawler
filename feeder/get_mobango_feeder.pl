#!/usr/bin/perl
use strict;
use LWP::UserAgent;
use HTML::TreeBuilder;
use IO::Handle;

my $ua = LWP::UserAgent->new;
$ua->timeout(60);
$ua->env_proxy;

open( FEED, ">mobango.url" );
FEED->autoflush(1);

my @urls = (
    'http://www.mobango.com/swarea/index.php/home?area=apps&platform=Android',
    'http://www.mobango.com/swarea/index.php/home?area=games&platform=Android',
);
my $url_base = "http://www.mobango.com";


foreach my $url (@urls){
    &process_feeder($url);
}

sub process_feeder{
    my $url = shift;
    my $res = $ua->get($url);
    while( not $res->is_success){
        $res = $ua->get($url);
    }
    if($res->is_success){
       my $webpage = $res->content;
       eval{
          my $tree = HTML::TreeBuilder->new;
          $tree->parse($webpage);
          my $category = $tree->look_down( class => "categories");
          my @li_nodes = $category->look_down("_tag","a");
          foreach(@li_nodes){
              next if $_->as_text =~ /All/;
              my $url = $url_base. $_->attr("href"); 
              print FEED $url,"\n"; 
          }
       };
       if($@){
           die "failed to extract mobango feeder url!";
       }
    }
}
close(FEED);
