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

my $app_main_dir = $conf->getAttribute('AppFolder');
my $dbh = $db_helper->get_db_handle;
my %cat_hash;
my %cat_relation;

my $sql="select i.*,s.app_self_id,k.app_unique_name, m.name ".
        "from app_source s,app_info i, app_apk k, market m  ".
        "where m.name='$market' ".
        "and k.need_submmit='yes' ".
        "and k.app_url_md5=i.app_url_md5 ".
        "and s.app_url_md5=k.app_url_md5 ".
        "and s.market_id=m.id";
my $sth=$dbh->prepare($sql);

$sth->execute or die "fail to execut $sql";
die "no rows\n" if($sth->rows==0);

&format_category;

#my $cmd = "tar -czvfP $market"."__$time.tar.gz ';
chdir( $app_main_dir );
while( my $hash=$sth->fetchrow_hashref)
{
    my $app_dir= get_app_dir($market,$hash->{'app_url_md5'});
  	
    next if not -e $app_dir ; 

    system("cp -r $app_dir shien");
    my $app_meta="shien/$app_dir/meta";

    open( META, ">>$app_meta") or die "fail to open $app_meta";
    select META;

    my $category = $hash->{'official_category'};
    print "\ntrustgo_category=".$cat_relation{$category}.".".$cat_hash{$category};
    close(META);
}

$dbh->disconnect;


sub format_category{
    my $cat_file = "trustgo_category.txt";

    open( CAT, "$cat_file");

    my $cat_id=0;
    my $sub_cat_id;
    my $index=0;

#    open ( FORMAT, ">cat.format");
    while( <CAT> ){
        my $category = $_;
        chomp($category);


        if ($category =~ /^ /){
            $sub_cat_id = $cat_id*100+$index;
            $category =~ s/^\s+//g;
            $category =~ s/\s+$//g;
            $cat_hash{$category} = $sub_cat_id;
            $cat_relation{$category} = $cat_id;
#            print FORMAT "\t$sub_cat_id   $category\n";
            ++$index;
        }else{
            $index=0;
            ++$cat_id;
            $cat_relation{$category} = 0;
            $cat_hash{$category} = $cat_id;
#            print FORMAT "\t$sub_cat_id   $category\n";
#            print FORMAT "$cat_id   $category\n";
        }
    }
}
