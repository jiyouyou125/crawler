#!/usr/bin/perl
BEGIN{unshift(@INC, $1) if ($0=~m/(.+)\//);}
use strict;
use warnings;

use LWP::Simple;
use Data::Dumper;
use MIME::Base64;
use IO::Handle;
use File::Path;
use Compress::Zlib;
use AMMS::Proto;
use Digest::MD5 qw(md5_hex);
use English;

use AMMS::Util;
use AMMS::AppFinder;
use AMMS::Downloader;
use AMMS::NewAppExtractor;
use AMMS::UpdatedAppExtractor;

my $context;
my $app_id;
my %app_result;
my $user_id;
my $device_id;
my $auth_sub_token;
my $market_api_url;
my $apk_download_url;
my $app_asin;
my $app_url_md5;

my $task_type   = $ARGV[0];
my $task_id     = $ARGV[1];
my $conf_file   = $ARGV[2];
my $market      = 'www.amazon.com';
my $downloader  = new AMMS::Downloader;

my $strAsin = "{\"asin\":\"B004S8GBU8\",\"version\":\"0\"}";  #can be change
my $strDeviceToken ="enc:g5EXbrWmKfoBPRfd6kIppoCpapIlnDQN9RvNUr9AsfJGvEG7T9uLeeQgrW3XqBqBEVwk/rASo/Myd25tjSNmM5j9F6Kaoeja0J+83dhF99ZWNSpxmKnK5J27gBr6G+myDXcoW4sKD8xYvdDzWXFaEn4/ROCiTdGi/mz9fgccZfyP8H9nmO06EbMVVT2/wjjoIplngxymrn6z9m7jCJKIfGe461sSzb7iF5grdJKxV7kwayk2w0k5LCehmkUbVjae1kyX+ZgVdjgcbufgNmP/ClT065TZrXqBmI+8q1+4KjQHp68X43L1fIc98AWnUMHS2ZjKOzppPRmJzjld1Urpe28TPUXysWCsJqBCChQ9Jo2Ckbc7EmpFq6NNcgFTejBthFm4dlNVaR5GaluY8CO4/r9/iKgyJoZw6MbasaUuzKH2o7El34uDatkUnhbkCo7CjPJS3OcUjSN9528gy3/Y+MhAQoh2XAalQ8NiCHzSN+xwVRhHRdz7C0b1PIVh0D313Ym5XdABfk/vSkV9WJ0D3PljX2A9ziVImGpHGs+i7eoiGa+D3Z+N3xgXu+BYE2r9/WxTQGS9gYWeE+YGqc3qW7WmDk6FiWh47yIZVToauJPe1mljOtX2TKr+BGmqpIxGuACkpFOEGYGFEx94gGYM8Q==}{iv:SVPpEP/KDhuzOoNGu4VhNw==}{key:SFbn7J+9P/3S+qLqIS2wDxJRcrk9ZH9VzBEnWJC3scM+eVes8A+wUGqpJL+6P26gRlgJWCGDajE2dJlKA9YReTJv4Otd25+nwLmBLaF2Cl4sor/EI/aikPlWMJG6BjtUJSaZ+T4inUG9WVuuf4P7jBHa1RZox6747DoUxTx3vxYst3y4ur4aNT8J2PEmIg3c+P2gnEeEVWVNEArMQxpW2kLVXqKA8pldl9E7czQv25hl43L3CTUZ2xghl/dqiDD+ihMcjuuVhsVlQW4u0DmZbdviQdLL2O9duJRZ4APigltp6v6pFzuyn/UIWd5iEz6SKPiGTux8+KQFHaZR4pHGkQ==}{name:QURQVG9rZW5FbmNyeXB0aW9uS2V5}{serial:MQ==}";
my $strDeviceKey ="MIIEwAIBADANBgkqhkiG9w0BAQEFAASCBKowggSmAgEAAoIBAQC3l9TyLoRJFVWvV/IhVpgyFZUYoUV+lWzWIXwpEnIqjAxtPH6ypMX1G/qg3/cFgPtTbOsJhXRbojf4kPsEx0V3jG/jFJcS7M2puLfN+As32WrxAQDP2nt6y5A2txj57hGWLKrqtHWxF0uYAQgjAo3rkOwXRrED44J6/TR3IUlG3fUcN8Inps1h8/LbN46fHjnsp03+unwM8BYEJq8CyCnY2KvWiPreP7+M/hE3EmQJkgEdSLwwcDlFyj0eRX";

die "\nplease check config parameter\n" unless init_gloabl_variable( );

my $db_handle=$db_helper->get_db_handle();
my $app_temp_dir= $conf->getAttribute( 'TempFolder' );
my $app_sample_dir  = $conf->getAttribute('SampleFolder');
my %apk = $db_helper->get_task_detail( $task_id );
my $md5_str=join "','",keys %apk;
$md5_str="'$md5_str'";
my $md5_sql = "select app_apk.app_url_md5,apk_url from app_info, app_apk where ".
            " app_info.app_url_md5 in ($md5_str) ".
            " and app_info.app_url_md5 = app_apk.app_url_md5 ".
            " and (app_info.status='success' or (app_info.status='update_to_date' and app_apk.status='fail') )";
my $md5_sth=$db_handle->prepare($md5_sql);
$md5_sth->execute;

my $hash_ref= $md5_sth->fetchall_hashref([ qw(app_url_md5) ]);
my %hash_merge =( %{$hash_ref} ); 
my $status=0;
my $tar_param=" ";
print "\nstart task $task_id";
foreach( keys %hash_merge ){
    my $apk_info=$hash_merge{$_};
    my $app_url_md5=$apk_info->{app_url_md5};
    my $app_asin=$apk_info->{apk_url};

    print "\nstart to deal with $app_url_md5";
    &download_app_apk($apk_info); 
    $db_helper->update_apk_info($apk_info);
        
    $tar_param .= get_app_dir($market,$app_url_md5)." ";
    $status = 1;##means there are some apps to submit
    print "\nend to deal with $app_url_md5";
    sleep(60);
}

if( $status ){
    my $tar_file        = $market.'__'.time.'.tgz';
    my $cmd = "cd $app_temp_dir; tar -czPf $app_sample_dir/$tar_file $tar_param ;cd -";
    unless ( execute_cmd($cmd) )
    {
        $logger->error("fail to tar app for $task_id");
        $status = 0;
    }

    $db_helper->save_package($task_id,$tar_file) if $status; 
}

$db_helper->update_task($task_id,'done');
print "\nend task $task_id";

exit;


sub download_app_apk 
{
    my $apk_file;
    my $apk_info= shift;
    my $app_url_md5=$apk_info->{app_url_md5};
    my $app_asin=$apk_info->{apk_url};

    $apk_info->{'status'}='fail';

    my $apk_dir= $app_temp_dir."/".get_app_dir( $market,$app_url_md5).'/apk';

    eval { 
        rmtree($apk_dir) if -e $apk_dir;
        mkpath($apk_dir);
    };
    if ( $@ )
    {
        warn("fail to create directory,App ID:$app_url_md5,Error:$EVAL_ERROR") ;
        return 0;
    }

    print "ASIN:$app_asin\n";

    my $cmd ="java -jar ".$conf->getAttribute('BaseBinDir')."/amazon/amazonDown.jar -a $app_asin" ;

    my $response;
    eval{
        local $SIG{ALRM} = sub   {   die "download timeout"};
        print "$cmd\n";
        alarm(300);
        $response =`$cmd`;
        alarm(0);
    };
    alarm(0);

    $response =~ s/\n/__n/g;

    if( $response !~ /right version is :(\d+)/){
        $logger->error("fail to purchaseItem:$app_asin");
        return 0;
    }

    if( $response !~ /download url is :{"downloadUrl":"(https:\/\/.*)?"}/){
        $logger->error("fail to get download URL:$app_asin");
        return 0;
    }
    my $download_url=$1;
    $apk_info->{'app_unique_name'} = &download_apk($apk_dir,$download_url) ;
    return 0 unless (defined $apk_info->{'app_unique_name'});

    $apk_info->{'status'}='success';

    return 1;
}

sub download_apk {
    my $apk_dir=shift;
    my $url=shift;

    ##download app
    my $ua = LWP::UserAgent->new();
    $ua->agent("AndroidDownloadManager");
    my $retry=0;
    my $response;
    do{
        ++$retry;
        eval{
            local $SIG{ALRM} = sub   {   die "download timeout"};
            alarm(300);
            $response = $ua->get($url);
            alarm(0);
        };
        alarm(0);
        unless ($response->is_success){
            $logger->error("fail to get APK:$app_asin");
            warn "fail to get apk for $app_url_md5";
            $logger->error("fail to get apk for $app_url_md5, error code:403") if $response->code==403;
            sleep(60*$retry);
        }
    }while( !$response->is_success and $retry<5); 
 
    return undef unless $response->is_success;
    #create apk file 
    my $unique_name=md5_hex($response->content);
    open(APK, ">$apk_dir/$unique_name.apk");
    binmode APK;
    print APK $response->content;
    close(APK);
   
    return $unique_name;
}

