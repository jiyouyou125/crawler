#!/usr/bin/perl 
#===============================================================================
#
#         FILE: ad.pl
#
#        USAGE: ./ad.pl
#
#  DESCRIPTION:
#
#      OPTIONS: ---
# REQUIREMENTS: ---
#         BUGS: ---
#        NOTES: ---
#       AUTHOR: YOUR NAME (),
#      COMPANY:
#      VERSION: 1.0
#      CREATED: 2011年10月13日 16时04分45秒
#     REVISION: ---
#===============================================================================

use strict;
use warnings;
use AMMS::Downloader;
use HTML::TreeBuilder;
use Encode;
use HTML::Entities;
use Data::Dumper;

my $downloader = new AMMS::Downloader;
my $content    = $downloader->download(
"http://www.mobango.com/swarea/index.php/home?idSubcategory=501&area=apps&standardFilter=most_downloaded&platform=Android"
);
my $url_base = "http://www.mobango.com";
my $pages = [];
if ( decode_entities( decode_utf8($content) ) =~
    m{.*<li class="next"[^>]*>[^<]*<a href="([^"]+)">}s )
{
    my $url_template = $1;
    my $total_pages = $1 if $url_template =~ s/pageNum=(\d+)&//;
    for ( 1 .. $total_pages ) {
        push @$pages, $url_base . $url_template . "&pageNum=" . $_;
    }
}
print Dumper($pages);
