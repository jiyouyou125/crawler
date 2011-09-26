#download url
BEGIN{unshift(@INC, $1) if ($0=~m/(.+)\//); $| = 1; }

use strict; 
use utf8; 
use HTML::Entities;
use DBI;
use Data::Dumper;
use Getopt::Std;
use Digest::MD5 qw(md5_hex);

use AMMS::Util;
use AMMS::Downloader;

binmode STDOUT, ":utf8";

my $market="market.android.com"; 
my $word_list="./wordlist/5000words.txt";
$word_list=$ARGV[0] if defined $ARGV[0];

die "\nplease check config parameter\n" unless init_gloabl_variable;#( $conf_file );

my $dbh = $db_helper->get_db_handle;
my $downloader = new AMMS::Downloader;
$downloader->timeout(120);

open(WORD,"<:utf8", "$word_list");
while(<WORD>){
    my $page_num=1;
    my $current_word=$_;
    chomp($current_word);

    print "\nstart word of $current_word\n";
    
    use URI::Escape qw( uri_escape_utf8 );
    my $encoded_current_word= uri_escape_utf8($current_word);

    ###try to search app
    while(1)
    {
        warn "Network is error" unless check_host_status;
        print "\nprocess the page $page_num of word '$current_word'";
        my $market_url="https://market.android.com/search?q=$encoded_current_word&c=apps&num=24&hl=en&start=".(($page_num - 1) * 24);
       
=pod
        #my $webpage=`curl --silent $market_url`;
        `lwp-download "$market_url"  $$`;
        local $/=undef;
        open(WEB,$$);
        my $webpage=<WEB>;
        unlink $$;
        close(WEB);
=cut
        my $webpage=$downloader->download($market_url); 
        print  FAIL "fail to search $current_word at $page_num\n" if ( $downloader->is_success);

        ###check if there are any apps for this word
        my @app_ids = &extract_app_id_from_file($webpage);  

        print "\nend of word $current_word" and last if not scalar @app_ids;
        &insert_app_source(@app_ids);

        ++$page_num;
        sleep(1);
   }

}

sub insert_app_source{

    my 	$sql='insert into app_source set '.
            ' app_url_md5=?'.
            ',app_self_id=?'.
            ',market_id=1'.
            ',feeder_id=0'.
            ',app_url=?'.
            ',status="undo"';

    my $sth = $dbh->prepare($sql);

    foreach (@_){
        my $app_self_id=$_;
        chomp($app_self_id);
        my $app_url='https://market.android.com/details?id='.$app_self_id;
        $sth->execute(md5_hex($app_url),$app_self_id,$app_url) or warn 
            $sth->errstr;
    }
}

sub extract_app_id_from_file{
    my $webpage=shift;  

    return () if $webpage =~ /We couldn't find anything/g;
    my @apps= ($webpage =~/<div class="thumbnail-wrapper goog-inline-block"><a href="\/details\?id=(.+?)\&feature=search_result"/g);
    return @apps;
}


exit;

sub usage
{
     print $_[0] if defined ($_[0]);
    print "\ Android crawler 1.0001 (Copyright(c) axplorer, inc), an app crawler.
\  
usage:  \
     perl download_app.pl [options...] <url>...  \
\
          -f <conf>         the config file to be loader during the download, \
                            if -f is not set, it will be default.cfg                  
          -h                Displays the usage (this message)\
          -V                Display version number\
     please set available downloader parameters in <conf> file\n";
}

sub version
{
    print "\
     downler sub system %Crawler::Config::get_Config{version}\
     Copyright (c) 2011 Axplorer company\
     All rights reserved\n";
}
