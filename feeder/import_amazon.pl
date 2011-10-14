use strict;

use AMMS::Util;

my $type = $ARGV[0];
my $conf_file   = $ARGV[1];

my %market_feed     = ( 'www.amazon.com'=>'amazon.url',
#        'market.android.com'=>'google.url',
        );

die "\nplease check config parameter\n" unless init_gloabl_variable( $conf_file );

my $dbh = $db_helper->get_db_handle;
foreach my $market ( keys %market_feed ) {
    next if defined($type) and $market ne $type;
    my $market_info=$db_helper->get_market_info($market);
    open(FEED, "feeder/$market_feed{$market}");
    my @feeds=<FEED>;
    foreach (@feeds){
        my $feed=$_;
        chomp($feed);
        $feed=trim($feed);
        
        my ($url,$parent_category,$sub_catgory) = split ';',$feed;
        my $sql = "insert into feeder set ".
            "feeder_url='$url'".
            ",market_id=".$market_info->{'id'}.
            ",parent_category='$parent_category' ";
        $sql .= ",sub_category=".$dbh->quote($sub_catgory)  if defined($sub_catgory);
#my $sth = $dbh->prepare($sql);

        $dbh->do($sql) or die $sql;
    }
}


exit;
