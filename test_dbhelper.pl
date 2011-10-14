#!/usr/bin/perl 
use strict;
use warnings;
use AMMS::DBHelper;
use Data::Dumper;

my $db_helper = new AMMS::DBHelper;

my $info = $db_helper->get_extra_info("f67edea3ebf2785c5c656612efc6da17");
print Dumper($info);
