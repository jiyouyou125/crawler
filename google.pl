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
use HTML::Entities;
use English;
use utf8;

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

my $market      = 'market.android.com';
my $downloader  = new AMMS::Downloader;

die "\nplease check config parameter\n" unless init_gloabl_variable( $conf_file );
die "\nfail o init apk downloader context\n" unless &init_apk_context;


my %month_map = (
        "January"=>"1","February"=>"2","March"=>"3","April"=>"4",
        "May"=>"5","June"=>"6","July"=>"7","August"=>"8",
        "September"=>"9","October"=>"10","November"=>"11","December"=>"12"
        );
my %category_mapping= (
    "Books & Reference"=>1,
    "Business"=>2,
    "Finance"=>2,
    "Comics"=>3,
    "Communication"=>4,
    "Education"=>5,
    "Entertainment"=>6,
    "Health & Fitness"=>9,
    "Libraries & Demo"=>11,
    "Lifestyle"=>19,
    "Medical"=>10,
    "Media & Video"=>707,
    "Music & Audio"=>709,
    "News & Magazines"=>14,
    "Personalization"=>12,
    "Widgets"=>1206,
    "Live Wallpaper"=>1205,
    "Photography"=>15,
    "Productivity"=>16,
    "Religion"=>26,
    "Shopping"=>17,
    "Social"=>18,
    "Sports"=>20,
    "Tools"=>22,
    "Transportation"=>13,
    "Travel & Local"=>21,
    "Weather"=>24,
    "Arcade & Action"=>801,
    "Brain & Puzzle"=>810,
    "Cards & Casino"=>803,
    "Casual"=>818,
    "Live Wallpaper"=>819,
    "Racing"=>811,
    "Sports Games"=>814,
    "Widgets"=>820,
        );


if( $task_type eq 'find_app' )##find new android app
{
    my $AppFinder   = new AMMS::AppFinder('MARKET'=>$market,'TASK_TYPE'=>$task_type);
    $AppFinder->addHook('extract_page_list', \&extract_page_list);
    $AppFinder->addHook('extract_app_from_feeder', \&extract_app_from_feeder);
    $AppFinder->run($task_id);
}
elsif( $task_type eq 'new_app' )##download new app info and apk
{
    my $NewAppExtractor= new AMMS::NewAppExtractor('MARKET'=>$market,'TASK_TYPE'=>$task_type,'NEXT_TASK_TYPE'=>'multi-lang');
    $NewAppExtractor->addHook('extract_app_info', \&extract_app_info);
    $NewAppExtractor->addHook('download_app_apk', \&download_app_apk);
    $NewAppExtractor->addHook('language_suffix', \&language_suffix);
    $NewAppExtractor->run($task_id);
}
elsif( $task_type eq 'update_app' )##download updated app info and apk
{
    my $UpdatedAppExtractor= new AMMS::UpdatedAppExtractor('MARKET'=>$market,'TASK_TYPE'=>$task_type);
    $UpdatedAppExtractor->addHook('extract_app_info', \&extract_app_info);
    $UpdatedAppExtractor->addHook('download_app_apk', \&download_app_apk);
    $UpdatedAppExtractor->addHook('language_suffix', \&language_suffix);
    $UpdatedAppExtractor->run($task_id);
}

exit;

sub language_suffix
{
    my ($worker, $hook, $web_lang) = @_;
    ${$web_lang}="&hl=en";
}

sub need_save_meta
{
    my ($worker, $hook, $app_info) = @_;

    $app_info->{description}="&hl=en";
}

sub extract_app_info
{
    my $tree;
    my @node;
    my @tags;
    my @kids;
    my ($worker, $hook, $webpage, $app_info) = @_;
    eval {
#    utf8::decode($webpage);
        $tree = HTML::TreeBuilder->new; # empty tree
###ignore meta tag, it block other tags
        $tree->warn(1);
        $tree->implicit_tags(0);
#$tree->ignore_tags(qw(meta));
        $tree->parse($webpage);

        my @nodes = $tree->find_by_attribute('class','doc-metadata-list');
        my @metas = $nodes[0]->content_list;
        $app_info->{min_os_version}= $metas[10]->as_text;
        $app_info->{min_os_version}=$1 if $metas[10]->as_text =~ /([\d\.]+)/;

        $app_info->{official_category}=$metas[12]->as_text;
        $app_info->{official_category} =~ s/&amp;/&/;
        $app_info->{trustgo_category_id}="-1";
        if (defined($category_mapping{$app_info->{official_category}})){
            $app_info->{trustgo_category_id}=$category_mapping{$app_info->{official_category}};
        }

        @metas = $tree->find_by_attribute('itemprop','name');
        $app_info->{app_name}=$metas[0]->attr('content');
        $app_info->{author}=$metas[1]->attr('content');
        
        my $meta = $tree->find_by_attribute('itemprop','image');
        $app_info->{icon}=$meta->attr('content');

        $meta=$tree->find_by_attribute('itemprop','ratingValue');
        $app_info->{official_rating_stars}=$meta->attr('content');

        $meta=$tree->find_by_attribute('itemprop','ratingCount');
        $app_info->{official_rating_times}=0;
        $app_info->{official_rating_times}=$1 if ref $meta and $meta->as_text =~ /([\d,]+)/;
        $app_info->{official_rating_times} =~ s/,//g;

        $meta=$tree->find_by_attribute('itemprop','publishDate');
        my $date_str = $meta->as_text; 
        $date_str =~ s/,/ /g;
        my ($monthy, $day, $year) = split " +", $date_str;
        $app_info->{last_update}="$year-$month_map{$monthy}-$day";

        $meta=$tree->find_by_attribute('itemprop','softwareVersion');
        $app_info->{current_version}=$meta->as_text;


        $app_info->{total_install_times}=0;
        $meta=$tree->find_by_attribute('itemprop','numDownloads');
        if( ref $meta ){ 
            my ($min_installs, $max_installs) = $meta->as_text =~ /(.*?)-(.*?)/;
            $min_installs =~ s/,//g;
            $app_info->{total_install_times}=$min_installs;
        }

        $meta=$tree->find_by_attribute('itemprop','price');
        $app_info->{price}= $meta->as_text;
        $app_info->{price}= 0 if $meta->as_text =~ /free/i;
        $app_info->{price}= "RMB:$1" if $meta->as_text =~ /￥([\d\.]+)/i;

        $meta=$tree->find_by_attribute('itemprop','contentRating');
        $app_info->{age_rating}= $meta->as_text;

        $app_info->{size}=0;
        $meta=$tree->find_by_attribute('itemprop','fileSize');
        my $size = $meta->as_text;
        $size =~ s/,//;
        if ($size =~ s/([\d\.]+)(\w)/$1/) {
            $size = $1*1024 if( uc($2) eq "M" );
            $app_info->{size}=int($size*1024); 
        }

        @node = $tree->look_down(id=>"doc-original-text");
        $app_info->{description}=$node[0]->as_HTML;
        $app_info->{description}=$1 if $app_info->{description} =~ /<div id="doc-original-text">(.*)<\/div>/;

        if ($webpage =~ /id="doc-original-text">(.*?)<\/div>/s){
            $app_info->{description}=$1; 
            $app_info->{description}=~s/<p>/__p/g;
            $app_info->{description}=~s/<\/p>/___p/g;
            $app_info->{description}=~s/<br>/__br/g;
            $app_info->{description}=~s/<.*?>//ig;
            $app_info->{description}=~s/___p/<\/p>/g;
            $app_info->{description}=~s/__p/<p>/g;
            $app_info->{description}=~s/__br/<br>/g;
            $app_info->{description}=~s/__br/<br>/g;
            decode_entities( $app_info->{description});
        }
            
        @node = $tree->look_down(class=>"doc-overview");
        my @tag = $node[0]->find_by_tag_name("a");
        $app_info->{website}=$1 if scalar(@tag) && $tag[0]->attr("href") =~ /q=(.*?)&/;

        @node = $tree->look_down(class=>"doc-whatsnew-container");
        $app_info->{whatsnew}=$node[0]->as_text;

        @node = $tree->look_down(class=>"doc-permission-description");
        $app_info->{permission} = [];
        foreach (@node){
            push @{$app_info->{permission}},$_->as_text;
        }


        @node = $tree->look_down(class=>"screenshot-carousel-content-container");
        if (scalar @node) {
            @kids = $node[0]->find_by_tag_name("img");
            $app_info->{screenshot} = [];
            foreach (@kids){
                push @{$app_info->{screenshot}},$_->attr("src");
            }
        }

        @node = $tree->look_down(_tag=>"object",class=>"doc-video");
        if (scalar @node) {
            @tag = $node[0]->find_by_tag_name("embed");
            $app_info->{video}=$1 if scalar @tag and $tag[0]->attr("src")=~/(.*?)&/;
        }

        $tree = $tree->delete;
    };
    $app_info->{status}='success';
    $app_info->{status}='fail' if $@;
    return scalar %{$app_info};
}

sub extract_page_list
{
    use File::Basename;

    my $tree;
    my @node;
    my @tags;

    my ($worker, $hook, $params, $pages) = @_;
    
    my $total_pages = 0;
    my $total_apps = 0;

    eval 
    {
        $tree = HTML::TreeBuilder->new; # empty tree
        $tree->parse($params->{'web_page'});
        
        @tags = $tree->find_by_tag_name('h2');
        $total_apps = $1 if $tags[0]->as_text =~ /of\s+(\d+)\s+for/;
        $total_pages = int($total_apps/9 +0.5);
        $tree = $tree->delete;
    };
    return 0 if $total_pages==0 ;

    my $base_url=$params->{'base_url'};
    for (1..$total_pages) 
    {
        push( @{ $pages }, "$base_url&p=".($_-1)*9);
    }
   
    return 1;
}

sub extract_app_from_feeder
{
    my $tree;
    my @nodes;

    my ($worker, $hook, $params, $apps) = @_;
 
    eval {

        $tree = HTML::TreeBuilder->new; # empty tree
        $tree->parse($params->{'web_page'});
        
        @nodes = $tree->look_down(class=>"app-download");
        foreach my $node (@nodes){
            my $tag_a = $node->find_by_tag_name("a");
            my $chomp_url = $tag_a->attr('href');
            my $header = head($chomp_url);
            $apps->{$2}=$1 if  defined($header->{_request}->{_uri}) and $header->{_request}->{_uri} =~
                /(https:\/\/market.android.com\/details\?id=(.*))/;
        }
        $tree = $tree->delete;
    };

    $apps={} if $@;

    return 1;
}

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
    my $self    = shift;
    my $hook_name  = shift;
    my $apk_info= shift;

    my $apk_file;
    my $md5 =   $apk_info->{'app_url_md5'};
    my $apk_dir= $self->{'TOP_DIR'}.'/'. get_app_dir( $market,$md5).'/apk';

    my $downloader  = new AMMS::Downloader;

    $app_package_name='';
    $app_package_name=$1 if $apk_info->{app_url}=~/https:\/\/market.android.com\/details\?id=(.*)/;
    $apk_info->{'apk_url'}=$app_package_name;
    if( $apk_info->{price} ne '0' ){
        $apk_info->{'status'}='paid';
        return 1;
    }
    $apk_info->{'status'}='undo';
    return 1;
    eval { 
        rmtree($apk_dir) if -e $apk_dir;
        mkpath($apk_dir);
    };
    if ( $@ )
    {
        $logger->error( sprintf("fail to create directory,App ID:%d,Error:
                    %s",$md5,$EVAL_ERROR) );
        $apk_info->{'status'}='fail';
        return 0;
    }

    print("start get asset id\n");
    ##app package name
    if( $apk_info->{'price'} ne "0" ){
        $apk_info->{'status'}='paid';
        return 0;
    }

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

    $apk_info->{'status'}='success';
    $apk_info->{'app_unique_name'} = $unique_name;

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
        warn "\nfail to get asset id for $app_package_name, error code:".$response->status_line;
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

sub extra_processing
{
    my ($worker, $hook, $app_info) = @_;

    my @langs=('zh_cn');

    my $url=$app_info->{'app_url'};

    my $downloader  = new AMMS::Downloader;
    foreach( @langs ){
        my $lang=$_;
        my %app_extra_info;
        $url .= "&hl=$lang";
        $downloader->timeout($conf->getAttribute("WebpageDownloadMaxTime"));
        my $app_page = $downloader->download($url);
        &extract_app_info(\$app_page,\%app_extra_info);
    }
}


