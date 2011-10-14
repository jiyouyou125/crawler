use strict;
use LWP::UserAgent;
use HTML::TreeBuilder;
use IO::Handle;
use Data::Dumper;
    
my $ua = LWP::UserAgent->new;
$ua->timeout(60);
$ua->env_proxy;


open(FEED,">tgbus-soft.url");
FEED->autoflush(1);

my $portal="http://dg.tgbus.com/soft/search-type-apk-0.html";

my $response = $ua->get($portal);

while( not $response->is_success){
    $response=$ua->get($portal);
}
                                         
if ($response->is_success) {
    my $tree;
    my @nodes;
    my @a_tags;

    my $webpage=$response->content;
	print $webpage;
	$tree = HTML::TreeBuilder->new;
	$tree->parse($webpage);
	@nodes = $tree->look_down(id => "typelist");
	@a_tags = $nodes[0]->find_by_tag_name("a");
	die "fail to extract tgbus feeder url" unless (scalar @a_tags);
	foreach(@a_tags[1..$#a_tags]){
		next if not ref $_;
		my $url_template  = "http://dg.tgbus.com/soft"."/".$_->attr("href");
		print FEED "$url_template\n"; 
	}

}
close(FEED);
exit;
