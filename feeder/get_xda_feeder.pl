#!/usr/bin/perl 
#===============================================================================
#
#         FILE: get_xda_feeder.pl
#
#        USAGE: ./get_xda_feeder.pl  
#
#  DESCRIPTION: 
#
#      OPTIONS: ---
# REQUIREMENTS: ---
#         BUGS: ---
#        NOTES: ---
#       AUTHOR: JamesKing (www.perlwiki.info), jinyiming456@gmail.com
#      COMPANY: China
#      VERSION: 1.0
#      CREATED: 2011年09月25日 08时17分52秒
#     REVISION: ---
#===============================================================================

use strict;
use warnings;
use LWP::UserAgent;
use HTML::TreeBuilder;
use IO::Handle;
use Carp;
use LWP::Simple;

my $ua = LWP::UserAgent->new;
$ua->timeout(60);
$ua->env_proxy;

open(FEED,">xda.url");
FEED->autoflush(1);

#'http://www.liqucn.com/os/android/rj/';
# http://www.liqucn.com/os/android/rj/
my @portals = (
    "http://android.xda.cn/html/list_index/1.html",
       );



foreach my $portal ( @portals ){
    my $response = $ua->get($portal);
    getstore($portal,'xda.html');
    while( not $response->is_success){
         $response=$ua->get($portal);
    }
                                                     
    if ($response->is_success) {
        my $tree;
        my $webpage=$response->content;
        eval {
            $tree = new HTML::TreeBuilder;
                    
            $tree->parse($webpage);
                         
            my @nodes = $tree->look_down( id => 'content_left_left_one');
            Carp::croak("not find node\n") unless @nodes;
            for(@nodes){
                my @tags = $_->find_by_tag_name('a');
                foreach my $tag(@tags){
                        next unless ref($tag);
                        my $href = $tag->attr('href');
                        map{
                            my $temp = $href ;
                            my $num = $_;
                            $temp =~ s/(\d+)(?=\.html$)/$1."_$num"/e;
                            print FEED $temp."\n";

                        } (1..3);
                }
            }
        };
        if($@){
            die "fail to $@\n";
        }
        $tree->delete;
    }
}
close(FEED);

