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

my $task_type   = $ARGV[0];
my $task_id     = $ARGV[1];
my $conf_file   = $ARGV[2];

my $context;
my $app_id;
my %app_result;
my $user_id;
my $device_id;
my $auth_sub_token;
my $market_api_url;
my $apk_download_url;
my $app_package_name;
my $app_url_md5;

my $market      = 'market.android.com';
my $downloader  = new AMMS::Downloader;

die "\nplease check config parameter\n" unless init_gloabl_variable( $conf_file );
die "\nfail o init apk downloader context\n" unless &init_apk_context;


#my $dbh = $db_helper->get_db_handle;
#my $sql = "select app_apk.* from app_source, app_apk where market_id =1 and app_source.app_url_md5 =app_apk.app_url_md5";
#my $sth = $dbh->prepare($sql);

#$sth->execute;

#while(my $hash=$sth->fetchrow_hashref){
    $ap_package_name=$hash->{apk_url};
    $app_url_md5=$hash->{app_url_md5};
    my %apk_info;
    &download_app_apk(\%apk_info); 
}
exit;


sub init_apk_context{
    $user_id='17558788718787595785';
    $device_id='4500701539983183731';
    $apk_download_url='http://android.clients.google.com/market/download/Download';
    $market_api_url='http://android.clients.google.com/market/api/ApiRequest';
    $auth_sub_token='DQAAALQAAACsAQnkrAOS7UJx7WhHfc9QeeE0Cj43HEPJgMTV5F5BxNVdNbavvOCETdycyZEmZOebzDRroVp0IfZtH2TwuMMVmMc-W-oxYDl03sAQ3tKlQIVqz_0zgkE04J8_KNMb0cyswERFI8XTWb8RYbwCHX24fJG-tCnFtj3XO6bl4cloE8rWXX0GwuVlG4jTmo6iBZdraKKoPXIF9dzcjsKQomWUE-y3h2FTzoDGMCZSOghqr0HlZ0XApZwK_4mxepQ3Q5M';

    $context = RequestContext->new;
    $context->unknown1(0);
    $context->version(1002012);
    $context->androidId("dead00beef");
    $context->userLanguage("en");
    $context->userCountry("us");
    $context->deviceAndSdkVersion("crespo:8");
    $context->operatorAlpha("T-Mobile");
    $context->simOperatorAlpha("T-Mobile");
    $context->operatorNumeric("310260");
    $context->simOperatorNumeric("310260");
    $context->clientId("aaa");
    $context->loggingId("615c740f5b48819a");
    $context->authSubToken($auth_sub_token);
}

sub download_app_apk 
{
    my $apk_info= shift;

    $apk_info->{'apk_url'}=$app_package_name;
    $apk_info->{'status'}='success';
    $apk_info->{'app_unique_name'} = $unique_name;
    $apk_info->{'app_url_md5'} = $app_url_md5;

    my $apk_file;
    my $apk_dir= $conf->getAttribute('AppFolder').'/'. get_app_dir( $market,$app_url_md5).'/apk';

    my $downloader  = new AMMS::Downloader;

    eval { 
        rmtree($apk_dir) if -e $apk_dir;
        mkpath($apk_dir);
    };
    if ( $@ )
    {
        $logger->error( sprintf("fail to create directory,App ID:%d,Error:
                    %s",$app_url_md5,$EVAL_ERROR) );
        $apk_info->{'status'}='fail';
        return 0;
    }

    print("start get asset id\n");
    ##app package name

    my $asset_id = &get_assetid();
    if ($asset_id eq 'fail' or $asset_id eq 'paid')
    {
        $apk_info->{'status'}=$asset_id;
        return 0;
    }
    print("end get asset id\n");

    print("start download apk\n");
    my $unique_name = &download_apk($apk_dir,$asset_id) ;
    if (not $unique_name)
    {
        $apk_info->{'status'}='fail';
        return 0;
    }

    return 1;
}

sub get_assetid{

    my $appsRequest=AppsRequest->new({
            query=>"pname:$app_package_name",
            startIndex=>0,
            entriesCount=>10,
            withExtendedInfo=>1
        });

    ###encode request
    my $appRequest = Request->new;
    $appRequest->context($context);
    $appRequest->RequestGroup({appsRequest=>$appsRequest});
    my $appReqest_encode = $appRequest->encode;
    my $appReqest_base64 = encode_base64( $appReqest_encode);

    ###send to google market to get app id
    my $ua = LWP::UserAgent->new();
    my %form;

    $form{version}=2;
    $form{request}=$appReqest_base64;
    $ua->agent("Android-Market/2 (sapphire PLAT-RC33); gzip");
    $ua->default_header('Content-Type'=>"application/x-www-form-urlencoded");
    $ua->default_header('Accept-Charset',"ISO-8859-1,utf-8;q=0.7,*;q=0.7");
    $ua->default_header('Cookie'=>"$auth_sub_token");

    my $response = $ua->post($market_api_url, \%form);
    if ( not $response->is_success ) {
        die "\nfail to get asset id for $app_package_name, error code:".$response->status_line;
        return 'fail';
    }
    
###get app assetid 
    my $response_str = $response->content;
    my $dest=Compress::Zlib::memGunzip($response_str);
    return 'fail' unless $dest; 
    my $response_ctx = Response->decode($dest) if( defined($dest) );
    my $group_list = $response_ctx->ResponseGroup;
    my $app_response;
    foreach (@{$group_list}){
        $app_response=$_->{appsResponse} and last if( defined($_->{appsResponse} ) );
    }

    if($app_response->{entriesCount} == 0){
        warn("\nFail to get info for $app_package_name, entry count is zero");
        return 'fail';
    }

    my $app_info = $app_response->{app};
    my $assetid= $$app_info[0]->{id};
    return 'paid' if defined($$app_info[0]->{price}) ;
   
    return $assetid;
}

sub download_apk {
    my $apk_dir=shift;
    my $assetid=shift;
##download app
    my $url_string="$apk_download_url?userId=$user_id&deviceId=$device_id&assetId=$assetid";

    my $ua = LWP::UserAgent->new();
    $ua->agent("AndroidDownloadManager");
    $ua->default_header('Cookie'=>"ANDROID=$auth_sub_token");
    my $response = $ua->get($url_string);
    if( !$response->is_success ) {
        return 0;
    }
 
    #create apk file 
    my $unique_name=md5_hex($response->content)."__".$app_package_name;
    eval { 
        rmtree($apk_dir) if -e $apk_dir;
        mkpath($apk_dir);
    };
    if ($@) {
        $logger->error("Counldn't create $apk_dir: $@ for $app_package_name");
        $app_result{$app_id}='fail';
        return undef;
    }

    open(APK, ">$apk_dir/$unique_name.apk");
    binmode APK;
    print APK $response->content;
    close(APK);
   
##get global unique id
    return $unique_name;
}

