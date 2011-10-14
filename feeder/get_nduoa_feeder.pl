use strict;
use LWP::UserAgent;
use HTML::TreeBuilder;
use IO::Handle;
    
my $ua = LWP::UserAgent->new;
$ua->timeout(60);
$ua->env_proxy;

open(FEED,">nduoa.url");
FEED->autoflush(1);

my $portal="http://www.nduoa.com";

my $response = $ua->get($portal);

while( not $response->is_success){
    $response=$ua->get($portal);
}
                                         
if ($response->is_success) {
    my $tree;
    my @node;
    my @a_tags;

    my $webpage=$response->content;

    my @a_links=$webpage=~/href="\/category\/(\d+)" rel/g;

    die "fail to extract Nduoa feeder url" unless (scalar @a_links); 

    foreach(@a_links){
        next unless defined $_;
        my $url_template="http://www.nduoa.com/apk/list/$_?order=download_count";
        print FEED "$url_template\n";
    };

}
close(FEED);
exit;
