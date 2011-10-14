#!/usr/bin/perl
use strict;
use LWP::UserAgent;
use HTML::TreeBuilder;
use IO::Handle;
    
my $ua = LWP::UserAgent->new;
$ua->timeout(60);
$ua->env_proxy;

open(FEED,">aimi8.url");
FEED->autoflush(1);
my $url_base="http://www.aimi8.com";
my $suffix="&page=1";
my $portal="http://www.aimi8.com/applist.html?ptn=apps";
    my $response = $ua->get($portal);
    while( not $response->is_success){
        $response=$ua->get($portal);
    }
    if ($response->is_success) {
        my $tree;
        my @allAppCategory;
        my @allAppATag;

        my $webpage=$response->content;
        eval {
            $tree = HTML::TreeBuilder->new; # empty tree
            $tree->parse($webpage);
            @allAppCategory = $tree->look_down("class","cates");
			if(scalar @allAppCategory){
				foreach my $item(@allAppCategory){
					push @allAppATag, $item->look_down("_tag","a");
				}
			}
			if(scalar @allAppATag){
				foreach my $ATag(@allAppATag){
					print FEED $url_base.$ATag->attr('href').$suffix."\n";
				}
			}
        };
        if($@){
            die "fail to extract Hiapk feeder url";
        }
    }
close(FEED);
exit;

