#!/usr/bin/perl 
use warnings;
use strict;

use Encode;
my $str = shift;
$str =~ s/\%u[0-9a-fA-F]{4}/pack("U",hex($1))/eg;
$str = encode("utf8",$str);
print $str;
