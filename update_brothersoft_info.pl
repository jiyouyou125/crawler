#!/usr/bin/perl 
#===============================================================================
#
#         FILE: update_brothersoft_info.pl
#
#        USAGE: ./update_brothersoft_info.pl
#
#  DESCRIPTION:
#
#      OPTIONS: ---
# REQUIREMENTS: ---
#         BUGS: ---
#        NOTES: ---
#       AUTHOR: YOUR NAME (),
#      COMPANY:
#      VERSION: 1.0
#      CREATED: 2011年10月14日 17时36分12秒
#     REVISION: ---
#===============================================================================

use strict;
use warnings;
use AMMS::Downloader;
use HTTP::Cookies;
use AMMS::DBHelper;
use AMMS::Util;
use Encode;
use AMMS::Config;

my $market_id  = shift;
my $downloader = new AMMS::Downloader;
my $dbhelper   = new AMMS::DBHelper;
$dbhelper->connect_db();
my $dbh        = $dbhelper->{DB_Handle};

my $cookie_jar = HTTP::Cookies->new;
$cookie_jar->set_cookie( undef, "sub_device", "2015", "/", "m.brothersoft.com",
    80 );
$downloader->{USERAGENT}->cookie_jar($cookie_jar);

my $sql = "select app_url_md5,app_url from app_info where market_id= ?";
my $sth = $dbh->prepare($sql) or die $dbh->errstr;
$sth->execute($market_id) or die $sth->errstr;
my @apps;
while ( my $row = $sth->fetchrow_hashref ) {
    push @apps, \%$row;
}

foreach my $app (@apps) {
    my $url_name = $1 if $app->{app_url} =~ /.*\/(.*?)\.html$/;
    my $url = "http://m.brothersoft.com/$url_name/";
    my $page = $downloader->download( $url );
    if ( $downloader->is_success ) {
        my $icon;
        my $total_install_times;
        if ( $page =~ m{<img src="([^"]+)"[^>]+?class="thumb"/>}s )
        {
            $icon  = $1;
        }
        if ( $page =~ m{<strong>Downloads:</strong>.*?([\d,]+)}s ) {
            $total_install_times = trim($1);
            $total_install_times =~ s/,//g;
        }
        my $sql;
        if($total_install_times){
            $sql ="update app_info set total_install_times=$total_install_times";
            $sql .= " where app_url_md5 = '".$app->{app_url_md5} ."'";
        }
        my $sth = $dbh->prepare($sql) or die $dbh->errstr;
        $sth->execute() or die $sth->errstr;
        my $config = new AMMS::Config;
        my $top_dir = $config->getAttribute( 'TempFolder' );
        my $app_dir= $top_dir.'/'.get_app_dir(&get_market($market_id),$app->{app_url_md5});
        if($icon =~ /^http/){
            my $icon_img = $downloader->download($icon);
            if($downloader->is_success){
                my $app_res_dir=$app_dir.'/res';
                $downloader->download_to_disk($icon,$app_res_dir,'icon');
                warn "failed to download icon" if not $downloader->is_success;
            }
        }
    }
}
sub get_market{
    my $market_id = shift;
    my $sql = "select name from market where id= ?";
    my $row = $dbh->selectrow_hashref($sql,undef,$market_id) or die "can't get market name:".$dbh->errstr;
    return $row->{name}; 
}
