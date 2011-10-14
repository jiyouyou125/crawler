use strict;
use LWP::UserAgent;
use HTML::TreeBuilder;
use IO::Handle;
    
my $ua = LWP::UserAgent->new;
#$ua->timeout(60);
$ua->env_proxy;
#$ua->agent("Mozilla/4.0 (Mozilla/4.0 (compatible; MSIE 6.0; Windows NT 5.2; SV1;.NET CLR 1.1.4322; .NET CLR 2.0.50727; InfoPath.2)");
#$ua->default_header('Accept','*/*');
#$ua->default_header('Accept-Language',"en;q=0.7");
#$ua->default_header('Accept-Encoding',"gzip, deflate");
#$ua->default_header('UA-CPU','x86');
#$ua->default_header('Cookie'=>"csm-hit=679.65;session-id-time=2082787201l;session-id=184-8203905-1115753;ubid-main=181-0088210-8441431;session-token=rlE8aOddJ6A3DmjlOBcayMpGV9sXJJOtoEyvGmKzRzk4UsOxjcuMjmaQFSFEvdYQ3i4GdSnwBdy0RLtHIp7K5iPV0Fd+kZCtDBe8S7edp3QOkVMMAiA0M7C9jVTv/8QYSwHjjUl6g/GVpZ+suw5jei/pzF2ck/rKgM2LG/DqLmHSeW1/iJ7aRj4073sel3tL/RORe2uznWWIk7c2i3KJxXR8DRrCm0T2lhWOIglk5bIK9L33DHwXDF03sAtemQ3z;apn-user-id=f2cce43e-5525-42f0-a0cc-7abc45b923a2");

open(URL,">amazon.url");
open(FEED,">amazon.cat");
URL->autoflush(1);
FEED->autoflush(1);

my $portal="http://www.amazon.com/s/ref=nb_sb_noss?url=search-alias%3Dmobile-apps&field-keywords=&x=12&y=19";
my $response = $ua->get($portal);

#get category URL from portal
while( not $response->is_success){
    $response=$ua->get($portal);
}
                                     
if ($response->is_success) {
    my $tree;
    my @node;
    my @tags;
    my @kids;

    my $webpage=$response->content;
    open(HTML,">html");
    print HTML $webpage;
    close(HTML);

    local $|;
    ++$|;
    eval {
        $tree = HTML::TreeBuilder->new; # empty tree
        $tree->parse($webpage);
        
        @node = $tree->look_down(id=>"refinements");
        @kids = $node[0]->content_list;

        my @li_tags = $kids[3]->content_list;
        foreach(@li_tags){
            my $a_tag=$_->find_by_tag_name("a");
            next unless defined $a_tag;
            my $parent_url=$a_tag->attr("href");
            print FEED "$parent_url\n";
        } 
    }
}
close(FEED);


open(FEED,"amazon.cat");
while(<FEED>){
    my $feed = $_;
    chomp($feed);

    $response = $ua->get($feed);

    while( not $response->is_success){
        $response=$ua->get($feed);
    }
                                     
    if ($response->is_success) {

        my $tree;
        my @node;
        my @tags;
        my @kids;

        my $webpage=$response->content;
        open(HTML,">html");
        print HTML $webpage;
        close(HTML);

        local $|;
        ++$|;
        eval {
            my $parent_category;
            $tree = HTML::TreeBuilder->new; # empty tree
            $tree->parse($webpage);
            
            @node = $tree->look_down(id=>"refinements");
            @kids = $node[0]->content_list;
            my @li_tags = $kids[3]->content_list;
            my $tag=$li_tags[1]->find_by_tag_name("strong");
            die $feed unless defined $tag;
            my $parent_category=$tag->as_text;

#print URL "$feed;$parent_category\n";    
            print URL "$feed\n";

            foreach(@li_tags[2..$#li_tags]){
                next unless ref $_;

                my $sub_category;
                my $a_tag=$_->find_by_tag_name("a");
                next unless defined $a_tag;
                my $sub_url=$a_tag->attr("href");
                my $span_tag=$_->find_by_attribute("class","refinementLink");
                if( defined $span_tag) {
                    $sub_category=$span_tag->as_text;
#print URL "$sub_url;$parent_category;$sub_category\n";    
                    print URL "$sub_url\n";
                }
            }


            next if $kids[4]->as_text =~ /Test Drive/;

            @li_tags = $kids[5]->content_list;
            foreach(@li_tags){
                next unless ref $_;

                my $sub_category;
                my $a_tag=$_->find_by_tag_name("a");
                next unless defined $a_tag;
                my $sub_url=$a_tag->attr("href");
                my $span_tag=$_->find_by_attribute("class","refinementLink");
                if( defined $span_tag) {
                    $sub_category=$span_tag->as_text;
#print URL "$sub_url;$parent_category;$sub_category\n";    
                    print URL "$sub_url\n";
                }
            }
        }
    }else{
        die $response->status_line;
    }
}

close(URL);
exit;
