#!/usr/bin/perl
BEGIN{unshift(@INC, $1) if ($0=~m/(.+)\//);}
use strict;
use warnings;

use LWP::Simple;
use Data::Dumper;
use MIME::Base64;
use IO::Handle;
use File::Path;
use Compress::Zlib;
use AMMS::Proto;
use Digest::MD5 qw(md5_hex);
use English;

use AMMS::Util;
use AMMS::AppFinder;
use AMMS::Downloader;
use AMMS::NewAppExtractor;
use AMMS::UpdatedAppExtractor;

my $url="";
my $category= $ARGV[0];
my $num_of_start = $ARGV[1];

my $market      = 'market.android.com';
my $downloader  = new AMMS::Downloader;

die "\nplease check config parameter\n" unless init_gloabl_variable;

open( FEEDER, "feeder/google.url") or die $!;
while(<FEEDER>){
    $url=$_;
    chomp($url);
    last if $url =~ /$category/;
}

die "Wrong Category ID" if $url eq ""; 

my $web_page = $downloader->download( $url );

die("fail to download webpage $category,reason:".$downloader->error_str) unless
$downloader->is_success;

utf8::decode($web_page);
my %params;
my @pages;

$params{'web_page'}=$web_page;
$params{'base_url'}=$url;
&extract_page_list( \%params,\@pages);

die('fail to extract sub url from feeder '.$category) unless (scalar @pages);

print "extract category $category\n";
open(LOG, ">>chomp.page");
foreach my $page ( @pages ) 
{
    print "pages $page\n";
    my $crawled = $1 if $page =~ /=(\d+$)/;
    next if $crawled<$num_of_start;
    my %apps;
    ##download the page that contains app
    $web_page = $downloader->download( $page );
    if ( not $downloader->is_success )
    {
        print LOG $page."\n";
        warn "fail to downlaod $page";
        next;
    }

    %params=();
    $params{'web_page'}=$web_page;
    &extract_app_from_feeder(\%params,\%apps);
    $db_helper->save_app_into_source( 0,$market,\%apps);
    
    my $app_list=join '  ', keys %apps;
    system("echo -n '$page\n$app_list ' >>$category.app;echo >>$category.app");
}
                   
exit;       
sub extract_page_list
{
    use File::Basename;

    my $tree;
    my @node;
    my @tags;

    my ($params, $pages) = @_;
    
    my $total_pages = 0;
    my $total_apps = 0;

    eval 
    {
        $tree = HTML::TreeBuilder->new; # empty tree
        $tree->parse($params->{'web_page'});
        
        @tags = $tree->find_by_tag_name('h2');
        $total_apps = $1 if $tags[0]->as_text =~ /of\s+([\d+,]+)\s+for/;
        $total_apps =~ s/,//g;
        $total_pages = int($total_apps/9 +0.5);
        $tree = $tree->delete;
    };
    return 0 if $total_pages==0 ;

    my $base_url=$params->{'base_url'};
    for (1..$total_pages) 
    {
        push( @{ $pages }, "$base_url&p=".($_-1)*9);
    }
   
    return 1;
}

sub extract_app_from_feeder
{
    my $tree;
    my @nodes;

    my ($params, $apps) = @_;
 
    eval {

        $tree = HTML::TreeBuilder->new; # empty tree
        $tree->parse($params->{'web_page'});
        
        @nodes = $tree->look_down(class=>"app-download");
        foreach my $node (@nodes){
            my $tag_a = $node->find_by_tag_name("a");
            my $chomp_url = $tag_a->attr('href');
            my $header = head($chomp_url);
            $apps->{$2}=$1 if  defined($header->{_request}->{_uri}) and $header->{_request}->{_uri} =~
                /(https:\/\/market.android.com\/details\?id=(.*))/;
        }
        $tree = $tree->delete;
    };

    $apps={} if $@;

    return 1;
}

