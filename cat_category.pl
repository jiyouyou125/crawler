#!/usr/bin/perl 
#===============================================================================
#
#         FILE: cat_category.pl
#
#        USAGE: ./cat_category.pl  
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
#      CREATED: 2011年09月27日 20时54分21秒
#     REVISION: ---
#===============================================================================

use strict;
use warnings;
use Data::Dumper;

my %hash;
while(<>){
    $hash{$_} = 1;
}

my @array = keys %hash;

print join "\t",@array;

