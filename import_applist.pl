#download url
BEGIN{unshift(@INC, $1) if ($0=~m/(.+)\//); $| = 1; }

use strict; 
use DBI;
use Data::Dumper;
use Getopt::Std;
use Digest::MD5 qw(md5_hex);

use AMMS::Util;

my $market="market.android.com"; 

die "\nplease check config parameter\n" unless init_gloabl_variable;#( $conf_file );

my $dbh = $db_helper->get_db_handle;


#my 	$sql='insert into app_source set '.
#            ' app_url_md5="'.md5_hex($apps->{$app_self_id}).'"'.
#            ',app_self_id='.$app_self_id.
#            ',market_id='.$market_id.
#            ',feeder_id='.$feeder_id.
#            ',app_url='.$self->{'DB_Handle'}->quote($apps->{$app_self_id}).
#            ',status="undo"';

my 	$sql='insert into app_source set '.
            ' app_url_md5=?'.
            ',app_self_id=?'.
            ',market_id=1'.
            ',feeder_id=0'.
            ',app_url=?'.
            ',status="undo"';

#if($self->{ 'DB_Handle' }->do($sql)<=0)
#my $sql = "insert into app_source set  check_time=now(),market='market.android.com',status='undo', app_id=?,package_name=?";
my $sth = $dbh->prepare($sql);

open(APP, "applist");
my @apps=<APP>;
foreach (@apps){
    my $app_self_id=$_;
    chomp($app_self_id);
    my $app_url='https://market.android.com/details?id='.$app_self_id;
    $sth->execute(md5_hex($app_url),$app_self_id,$app_url);
}

$dbh->disconnect;


