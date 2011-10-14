#!/usr/bin/perl 
#===============================================================================
#
#         FILE: test_download.pl
#
#        USAGE: ./test_download.pl  
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
#      CREATED: 2011年09月27日 15时11分16秒
#     REVISION: ---
#===============================================================================

use strict;
use warnings;
use HTTP::Request;
use LWP::UserAgent;
use Data::Dumper;

my $ua = LWP::UserAgent->new;

my $request = HTTP::Request->new;
$request->method("GET");
$request->uri("http://dg.tgbus.com/game/item-898.html");

my $res = $ua->request($request);

print Dumper($res);

