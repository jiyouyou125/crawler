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

my $market="market.android.com"; 

die "\nplease check config parameter\n" unless init_gloabl_variable;#( $conf_file );

my $dbh = $db_helper->get_db_handle;

my $sql="select i.*,s.app_self_id,k.app_unique_name, m.name from app_source s,app_info i, app_apk k, market m where need_submmit='yes' and k.app_url_md5=i.app_url_md5 and s.app_url_md5=k.app_url_md5 and s.market_id=m.id";
my $sth=$dbh->prepare($sql);
$sth->execute;

die "no rows\n" if($sth->rows==0);
my $cmd = 'tar -czvfP mumayi.tar.gz ';
while( my $hash=$sth->fetchrow_hashref)
{
    my $app_dir= get_app_dir($hash->{'name'},$hash->{'app_url_md5'});
  	
    next if not -e $app_dir ; 
    system("mkdir -p $app_dir");
    my $app_meta="$app_dir/meta";

   $cmd .=substr($hash->{'app_url_md5'}, 0, 2).'/'.substr($hash->{'app_url_md5'}, 2, 2).'/'.$hash->{'app_url_md5'}.' ';
#open ( OUT, ">>has_meta");
#print OUT $hash->{'app_url_md5'}."\n";
#close( OUT);
    open( META, ">$app_meta") or die "fail to open";
    select META;

    print "\napp_name=".$hash->{'app_name'}; 
    print "\napp_unique_name=".$hash->{'package_name'}; 
    print "\nofficial_category=".$hash->{'official_category'}; 
    print "\nauthor=".$hash->{'author'}; 
    print "\nsupport_os=".$hash->{'support_os'}; 
    print "\napp_capacity=".$hash->{'app_capacity'}; 
    print "\nos_version=".$hash->{'min_os_version'}; 
    print "\nofficial_rating=".$hash->{'official_rating_stars'}; 
    print "\nofficial_rating_users=".$hash->{'official_rating_users'}; 
    print "\nlast_update=".$hash->{'last_update'}; 
    print "\nsize=".$hash->{'size'}; 
    print "\nprice=".$hash->{'price'}; 
    print "\ncurrent_version=".$hash->{'current_version'}; 
    print "\ntotal_install_times=".$hash->{'total_install_times'}; 
    print "\nbuy_link=".$hash->{'buy_link'}; 
    print "\nwebsite=".$hash->{'website'}; 
    print "\ncontent_rating=".$hash->{'content_rating'}; 
    close(META);
}

print $cmd;
$dbh->disconnect;


