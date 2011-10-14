#!/usr/bin/perl 
#===============================================================================
#
#         FILE: test_price.pl
#
#        USAGE: ./test_price.pl
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
#      CREATED: 2011年10月14日 10时42分20秒
#     REVISION: ---
#===============================================================================

use strict;
use warnings;
use Encode;
use AMMS::Downloader;
use HTML::TreeBuilder;
use LWP::Simple;

open FILE, "<", "brothersoft.price" or die "can't open the file:$!";
while (<FILE>) {
    my $url     = ( split /\s/ )[1];
    my $content = get($url);
    $content = decode_utf8($content);

    my $tree     = HTML::TreeBuilder->new;
    my $app_info = {};
    $tree->parse($content);

    #last_update,author,price
    my $license = $tree->look_down( class => "license" );
    my $license_price = $license->look_down( "_tag", "div", "class", "free_p" );
    my ( $license_text, $price ) =
      ( $license_price->as_text =~ /:(.*?)\/(.*)/ );
    $app_info->{price} = 0           if $price =~ /(Free|-)/;
    $app_info->{price} = "USD:" . $1 if $price =~ /\$([.\d]+)/;
    $app_info->{price} = "EUR:" . $1 if $price =~ /E(?:UR)?([.\d]+)/;
    if ( $price =~ /^\s*([.\d]+)\s*$/ ) {
        my $tmp_price = $1;
        if ( $tmp_price =~ /^0([.0]+)?$/ ) {
            $app_info->{price} = 0;
        }
        else {
            $app_info->{price} = "USD:" . $tmp_price;
        }
    }
    print $url, "-----", $app_info->{price},"\n";
}

