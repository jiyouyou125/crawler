use strict;
use LWP::UserAgent;
use HTML::TreeBuilder;
use IO::Handle;
    
my $ua = LWP::UserAgent->new;
$ua->timeout(60);
$ua->env_proxy;

open(FEED,">hiapk.url");
FEED->autoflush(1);

my $apps_portal="http://sc.hiapk.com/apps_0_1_1";
my $games_portal="http://sc.hiapk.com/games_0_1_1";

foreach my $portal ( $apps_portal,$games_portal){
    my $response = $ua->get($portal);

    while( not $response->is_success){
        $response=$ua->get($portal);
    }
                                         
    if ($response->is_success) {
        my $tree;
        my @node;
        my @li_kids;

        my $webpage=$response->content;
        eval {
            $tree = HTML::TreeBuilder->new; # empty tree
            $tree->parse($webpage);
            
            @node = $tree->look_down(id=>"Search_CategoryTab");
            @li_kids = $node[0]->content_list;

            foreach(@li_kids){
                next unless ref $_;
                my $a_tag=$_->find_by_tag_name("a");
                next unless defined $a_tag;
                my $category_number=$1 if $a_tag->attr("href")=~/(\d+)/g;
                my $url=$portal;
                $url=~ s/(.*?)(_0_1_1)/$1_${category_number}_1_1/g;
                print FEED "$url\n";
            } 
        };
        if($@){
            die "fail to extract Hiapk feeder url";
        }
    }
}
close(FEED);
exit;
