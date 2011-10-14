#!/usr/bin/perl 
#===============================================================================
#
#         FILE: test.pl
#
#        USAGE: ./test.pl  
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
#      CREATED: 2011年09月28日 19时04分07秒
#     REVISION: ---
#===============================================================================

use strict;
use warnings;
use utf8;
use Encode;

my $file = shift;

my $content = do { local $/; open my $handle,"<",$file;<$handle>};

if(decode("gb2312",$content) =~ /手机软件.*?<a[^>]+>(.*?)<\/a>/){
    print "matched";
}else{
    print "nO";
}


