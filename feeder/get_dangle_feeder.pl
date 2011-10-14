use strict;
use LWP::UserAgent;
use HTML::TreeBuilder;
use IO::Handle;
    
my $ua = LWP::UserAgent->new;
$ua->timeout(60);
$ua->env_proxy;

open(FEED,">dangle.url");
FEED->autoflush(1);

my $soft_portal="http://android.d.cn/software/";
my $game_portal="http://android.d.cn/game/";
my $online_portal="http://android.d.cn/netgame/hot";
my $url_base="http://android.d.cn";


foreach my $portal ($soft_portal, $game_portal){
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

        @node=$tree->look_down("_tag","div","class","category");
        
        ##applications
        my @a_links=$node[0]->find_by_tag_name("a");
        die "fail to extract DangLe feeder url" unless (scalar @a_links); 
        foreach(@a_links){
            next unless defined $_;
            print FEED $url_base.$_->attr("href")."\n";
        }

    }
}
            
print FEED "$online_portal\n";
close(FEED);
exit;
