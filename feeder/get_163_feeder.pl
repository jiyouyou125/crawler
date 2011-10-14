use strict;
use LWP::UserAgent;
use HTML::TreeBuilder;
use IO::Handle;
    
my $ua = LWP::UserAgent->new;
$ua->timeout(60);
$ua->env_proxy;

open(FEED,">163.url");
FEED->autoflush(1);

my $portal="http://m.163.com/android/#cat";
my $url_base="http://m.163.com";


my $response = $ua->get($portal);
while( not $response->is_success){
    $response=$ua->get($portal);
}
                                         
if ($response->is_success) {
    my $tree;
    my @node;
    my @a_tags;

    my $webpage=$response->content;
    $tree = HTML::TreeBuilder->new; # empty tree
    $tree->parse($webpage);

    @node=$tree->look_down("_tag","div","id","apps-cat-overlay");
    
    ##applications
    my @a_links=$node[0]->find_by_tag_name("a");
    die "fail to extract 163 feeder url" unless (scalar @a_links); 
    foreach(@a_links){
        next unless defined $_;
        print FEED $url_base.$_->attr("href")."\n";
    }
}
            
close(FEED);
exit;
