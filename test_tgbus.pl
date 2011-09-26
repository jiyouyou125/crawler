#!/usr/bin/perl 
use warnings;
use strict;
use utf8;
use Data::Dumper;
use HTML::TreeBuilder;
use LWP::Simple;
use HTML::Entities;
require "tgbus.pl";

=pod
my $html = get("http://dg.tgbus.com/game/item-405.html");
open FILE,">","a.html" or die "can't open:$!";
print FILE $html;
my $url_base = "http://dg.tgbus.com/game";
=cut
my $app_info;
my $content = do{ local $/ = undef ;open FILE,"<","item-405.html";<FILE>;};

&extract_app_info(undef,undef,$content,$app_info);

