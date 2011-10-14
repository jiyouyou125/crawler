#!/usr/bin/perl 
#===============================================================================
#
#         FILE: a.pl
#
#        USAGE: ./a.pl
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
#      CREATED: 2011年10月12日 16时42分45秒
#     REVISION: ---
#===============================================================================

use strict;
use warnings;
use HTML::TreeBuilder;
use LWP::Simple;

my $content = get('http://www.mobango.com/swarea/index.php?page=SoftwareDetail&area=games&standardFilter=most_downloaded&platform=Android&idsw_mobango=45009&title=Bingo&listNum=2#');

my $tree = HTML::TreeBuilder->new;
$tree->parse($content);
my $info_list = $tree->look_down(id=>"info-list-details");
print $info_list->as_text;
