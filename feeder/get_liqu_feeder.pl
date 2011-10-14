#!/usr/bin/perl
use strict;
use LWP::UserAgent;
use HTML::TreeBuilder;
use IO::Handle;
    
my $ua = LWP::UserAgent->new;
$ua->timeout(60);
$ua->env_proxy;

open(FEED,">liqu.url");
FEED->autoflush(1);

#'http://www.liqucn.com/os/android/rj/';
# http://www.liqucn.com/os/android/rj/
my @portals = (
        'http://www.liqucn.com/os/android/rj/',
        'http://www.liqucn.com/os/android/yx/',
        'http://www.liqucn.com/os/android/zt/',
       );


foreach my $portal ( @portals ){
    my $response = $ua->get($portal);
    while( not $response->is_success){
         $response=$ua->get($portal);
    }
                                                     
    if ($response->is_success) {
        my $tree;
        my $webpage=$response->content;
        eval {
            $tree =
                    HTML::TreeBuilder->new;
            $tree->parse($webpage);
                         
            my @nodes = $tree->look_down( class => 'last_cat' );
            for(@nodes){
                my @tags = $_->find_by_tag_name('a');
                foreach my $tag(@tags){
                        next unless ref($tag);
                #    GBA NES(FC) MD SFC
                #        GB/GBC 
                        # filter 刷机and模拟器     
                        next if $tag->as_text =~ m/刷机|数据包|GB|NE|MD|SF/i;                   
                        print $tag->as_text."\n";
                        print FEED $tag->attr('href')."\n";
                }
            }
        };
        if($@){
            die "fail to $@\n";
        }
    }
}
close(FEED);

