use strict;
use LWP::UserAgent;
use HTML::TreeBuilder;
use IO::Handle;
    
my $ua = LWP::UserAgent->new;
$ua->timeout(60);
$ua->env_proxy;

open(FEED,">appchina.url");
FEED->autoflush(1);

my $portal="http://www.appchina.com";
#my $host="http://m.appchina.com//market-web/lemon";

my $response = $ua->get($portal);

while( not $response->is_success){
    $response=$ua->get($portal);
}
                                         
if ($response->is_success) {
    my $tree;
    my @node;
    my @a_tags;

    my $webpage=$response->content;
    eval {
        $tree = HTML::TreeBuilder->new; # empty tree
        $tree->ignore_unknown(0);
        $tree->parse($webpage);
            
##apps
        @node = $tree->look_down( class=>"app");
        @a_tags = ($node[0]->content_list)[1]->find_by_tag_name("a");

        foreach(@a_tags){
            next unless ref $_;
            print FEED "$portal".$_->attr("href")."\n";
        };

        @node = $tree->look_down( class=>"game");
        @a_tags = ($node[0]->content_list)[1]->find_by_tag_name("a");
        foreach(@a_tags){
            next unless ref $_;
            print FEED "$portal".$_->attr("href")."\n";
        };

        if($@){
            die "fail to extract Hiapk feeder url";
        }
    }
}
close(FEED);
exit;
