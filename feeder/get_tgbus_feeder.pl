use strict;
use LWP::UserAgent;
use HTML::TreeBuilder;
use IO::Handle;
use Data::Dumper;

my $ua = LWP::UserAgent->new;
$ua->timeout(60);
$ua->env_proxy;

open( FEED, ">tgbus.url" );
FEED->autoflush(1);

my $portal  = "http://dg.tgbus.com/game/search-size-0-158,178.html";
my $portal1 = "http://dg.tgbus.com/soft/search-size-0-158,178.html";
my @lines;
&get_feeder_list($portal,"http://dg.tgbus.com/game");
&get_feeder_list($portal1,"http://dg.tgbus.com/soft");

sub get_feeder_list {
    my ($url,$base_url) = @_;
    my $response = $ua->get($url);
    while ( not $response->is_success ) {
        $response = $ua->get($url);
    }
    if ( $response->is_success ) {
        $response = $ua->get($url);
        my $tree;
        my @nodes;
        my @a_tags;

        my $webpage = $response->content;
        print $webpage;
        $tree = HTML::TreeBuilder->new;
        $tree->parse($webpage);
        @nodes = $tree->look_down( id => "typelist" );
        @a_tags = $nodes[0]->find_by_tag_name("a");
        die "fail to extract tgbus feeder url" unless ( scalar @a_tags );
        foreach ( @a_tags[ 1 .. $#a_tags ] ) {
            next if not ref $_;
            my $url_template =
              $base_url . "/" . $_->attr("href");
			print $url_template,"\n";
            print FEED "$url_template\n";
        }

    }
}    ## --- end sub get_feeder_list

close(FEED);
exit;
