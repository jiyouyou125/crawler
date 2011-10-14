#!/usr/bin/perl 
use warnings;
use strict;

open FILE,">", "189store.url" or die "can't open file: $!";

my $url = "http://www.189store.com/index.php?app=apps&act=osapp&osId=403";

print FILE $url;

close FILE;
