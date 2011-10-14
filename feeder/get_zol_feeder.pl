#!/usr/bin/perl 
use warnings;
use strict;

open FILE,">", "zol.url" or die "can't open file: $!";

my $url = "http://sj.zol.com.cn/android/";

print FILE $url;

close FILE;
