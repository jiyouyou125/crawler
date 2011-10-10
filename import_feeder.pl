use strict;

use AMMS::Util;

my $type = $ARGV[0];
my $conf_file   = $ARGV[1];

my %market_feed     = (
    'www.aimi8.com'=>'aimi8.url',
    'www.mumayi.com'=>'mumayi.url',
    'www.amazon.com'=>'amazon.url',
    'www.hiapk.com'=>'hiapk.url',
    'www.gfan.com'=>'gfan.url',
    'www.appchina.com'=>'appchina.url',
    'market.android.com'=>'google.url',
    'www.nduoa.com'=>'nduoa.url',
    'www.eoemarket.com'=>'eoemarket.url',
    'www.goapk.com'=>'goapk.url',
    'android.d.cn'=>'dangle.url',
    'm.163.com'=>'163.url',
	'dg.tgbus.com' => 'tgbus.url',
    'www.anfone.com'=>'anfone.url',
	'www.189store.com' =>'189store.url',
    'dg.tgbus.com'=>'tgbus.url',
    'sj.zol.com.cn' => 'zol.url',
    'www.brothersoft.com' => 'brothersoft.url',
    'm.1mobile.com' => '1mobile.url',
        );

die "\nplease check config parameter\n" unless init_gloabl_variable( $conf_file );

my $dbh = $db_helper->get_db_handle;
foreach my $market ( keys %market_feed ) {
    if (defined($type)){
        next if $market ne $type;
    }
    my $market_info=$db_helper->get_market_info($market);
    my $sql = "replace into feeder set feeder_url=?,market_id=".$market_info->{'id'};
    my $sth = $dbh->prepare($sql);

    open(FEED, "feeder/$market_feed{$market}");
    my @feeds=<FEED>;
    foreach (@feeds){
        my $feed=$_;
        chomp($feed);
        $feed=trim($feed);
        $sth->execute($feed);
    }
}


exit;
