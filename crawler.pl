#!/usr/bin/perl 
#===============================================================================
#
#         FILE: crawler.pl
#
#        USAGE: ./crawler.pl  
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
#      CREATED: 2011年10月06日 09时41分58秒
#     REVISION: ---
#===============================================================================

use strict;
use warnings;
use 5.010;
use Mojo::UserAgent;
use Mojo::IOLoop;
use DBI;

my @feeder = ();
my @page_list = ();
my @urls = ();

my $ua = Mojo::UserAgent->new(max_redirects => 5);
my $crawl;

$crawl = sub{
	my $id = shift;
	return Mojo::IOLoop->timer( 2 => sub { $crawl->($id)});
	
	#Fetch non-blocking just by adding a callback
	$ua->get(
	 	my($self, $tx) = @_;
		say "[$id] $url";
		$tx->res->dom()->each(sub{
		my $e = shift;
		my $url = Mojo::URL->new($e->{href})->to_abs($tx->req->url);
		say " -> $url";
		
		# Enqueue
		push @urls, $url;
		});
	
	# Next
	$crawl->($id);
	);
};

$crawl->($_) for 1..3;
Mojo::IOLoop->start;
sub get_app_from_feeder{
	
}
sub get_page_list{
}
sub extract_app_info{

}

sub get_feeder_url{
    my($market_id) = @_;
    $sql = "select * from feeder where market_id=?";
    my $smt = $dbh->prepare($sql);
    $smt->excute($market_id);
}
