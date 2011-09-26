#download url
BEGIN{unshift(@INC, $1) if ($0=~m/(.+)\//); $| = 1; }

use strict; 
use DBI;
use Data::Dumper;
use Getopt::Std;
use File::Path;
use open ':utf8';
use Digest::MD5 qw(md5_hex);
use AMMS::Util;
use AMMS::Downloader;

die "\nplease check config parameter\n" unless init_gloabl_variable;#( $conf_file );
my $from=$ARGV[0];
my $limit=$ARGV[1];
my $market="market.android.com"; 
my $app_main_dir=$conf->getAttribute('AppFolder');
my $dbh = $db_helper->get_db_handle;

my $sql="select app_info.* from app_source ,app_info  ".
        "where app_source.app_url_md5=app_info.app_url_md5 ".
        "and app_source.market_id=1 order by app_info.app_url_md5 ".
        "asc limit $from, 20000";
my $sth=$dbh->prepare($sql);
$sth->execute;
die "no rows\n" if($sth->rows==0);

chdir($app_main_dir);
open(FAIL, ">>app.page.fail.$$") or die $!;
open(EXIST, ">>app.page.exist") or die $!;
open(SUCCESS, ">>app.page.success") or die $!;
my $downloader  = new AMMS::Downloader;
while( my $hash=$sth->fetchrow_hashref)
{
    print "\nstart ".$hash->{'app_url_md5'}; 
    my $app_dir= get_app_dir($market,$hash->{'app_url_md5'});
  	
    mkpath $app_dir if not -e $app_dir ; 

    my $page_file ="$app_dir/page";
    print EXIST $hash->{'app_url_md5'}."\n" and next if -e $page_file; 
#system("mkdir -p $app_dir");

    print "\ndownload ".$hash->{'app_url_md5'}; 
    my $page = $downloader->download($hash->{'app_url'}.'&hl=en');
    print FAIL $hash->{'app_url_md5'} and next if not $downloader->is_success;

    print "\nsave".$hash->{'app_url_md5'}; 
    open( PAGE , ">$page_file") or die "fail to open $page_file";
    print PAGE $page; 
    close( PAGE );
    print "\nend ".$hash->{'app_url_md5'}; 
    print SUCCESS $hash->{'app_url_md5'};
}

$dbh->disconnect;


