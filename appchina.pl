#!/usr/bin/perl
BEGIN{unshift(@INC, $1) if ($0=~m/(.+)\//);}
use strict;
use warnings;

use AMMS::Util;
use AMMS::AppFinder;
use AMMS::Downloader;
use AMMS::NewAppExtractor;
use AMMS::UpdatedAppExtractor;

my $task_type   = $ARGV[0];
my $task_id     = $ARGV[1];
my $conf_file   = $ARGV[2];

my $market      = 'www.appchina.com';
my $url_base    = 'http://www.appchina.com';
my $downloader  = new AMMS::Downloader;

my %category_mapping=(
        "\x{7CFB}\x{7EDF}.\x{4E3B}\x{9898}.\x{8F93}\x{5165}\x{6CD5}"=>22,
        "\x{7F51}\x{7EDC}.\x{901A}\x{4FE1}.\x{90AE}\x{4EF6}"=>4,
        "\x{97F3}\x{4E50}.\x{89C6}\x{9891}.\x{56FE}\x{50CF}"=>7,
        "\x{8D44}\x{8BAF}.\x{9605}\x{8BFB}.\x{5546}\x{52A1}.\x{8BCD}\x{5178}"=>"14,1",
        "\x{804A}\x{5929}.\x{901A}\x{8BAF}.\x{793E}\x{4EA4}"=>18,
        "\x{65E5}\x{5E38}.\x{4FE1}\x{606F}.\x{5730}\x{56FE}"=>"21,19",
        "\x{4F11}\x{95F2}.\x{5A31}\x{4E50}.\x{5065}\x{5EB7}"=>6,

        "\x{52A8}\x{4F5C}\x{7ADE}\x{6280}"=>823,
        "\x{7B56}\x{7565}\x{6E38}\x{620F}"=>815,
        "\x{89D2}\x{8272}\x{517B}\x{6210}"=>812,
        "\x{5C04}\x{51FB}\x{6E38}\x{620F}"=>821,
        "\x{4F53}\x{80B2}\x{8D5B}\x{8F66}"=>814,
        "\x{76CA}\x{667A}\x{68CB}\x{724C}"=>803,
        "\x{6A21}\x{62DF}\x{8F85}\x{52A9}"=>813,
                );
die "\nplease check config parameter\n" unless init_gloabl_variable( $conf_file );

if( $task_type eq 'find_app' )##find new android app
{
    my $AppFinder   = new AMMS::AppFinder('MARKET'=>$market,'TASK_TYPE'=>$task_type);
    $AppFinder->addHook('extract_page_list', \&extract_page_list);
    $AppFinder->addHook('extract_app_from_feeder', \&extract_app_from_feeder);
    $AppFinder->run($task_id);
}
elsif( $task_type eq 'new_app' )##download new app info and apk
{
    my $NewAppExtractor= new AMMS::NewAppExtractor('MARKET'=>$market,'TASK_TYPE'=>$task_type);
    $NewAppExtractor->addHook('extract_app_info', \&extract_app_info);
    $NewAppExtractor->run($task_id);
}
elsif( $task_type eq 'update_app' )##download updated app info and apk
{
    my $UpdatedAppExtractor= new AMMS::UpdatedAppExtractor('MARKET'=>$market,'TASK_TYPE'=>$task_type);
    $UpdatedAppExtractor->addHook('extract_app_info', \&extract_app_info);
    $UpdatedAppExtractor->run($task_id);
}

exit;

sub extract_app_info
{
    my $tree;
    my @node;
    my @tags;
    my ($worker, $hook, $webpage, $app_info) = @_;

    eval {
#utf8::encode($webpage);

        $tree = HTML::TreeBuilder->new; # empty tree
        $tree->ignore_unknown(0);
        $tree->parse($webpage);
        

        @node= $tree->look_down("_tag","tr","class","portal-item-screenshot");
        if (scalar @node ) {
            $app_info->{screenshot} = [];
            foreach (@node){
                next if not ref $_;
                push @{$app_info->{screenshot}},($_->content_list)[0]->attr("sr");
            }
        }

        @tags= $tree->find_by_attribute(class=>"icon");
        $app_info->{icon}=$tags[0]->attr("src") if ref $tags[0];
        @tags= $tree->find_by_attribute( class=>"app-android-version");
        $app_info->{min_os_version}=$1 if ref $tags[0] and $tags[0]->as_text =~ /([\d\.]+)/;
        @node= $tree->find_by_attribute(class=>"yyh-round-top-center");
        @tags= $node[0]->find_by_tag_name("a");
        $app_info->{official_category}= $tags[1]->as_text if ref $tags[1];


        ##get meta data from mobile API
        my $app_self_id = $1 if $app_info->{app_url}=~/soft_detail_(\d+)/; 
        my $content='key=&referer=00b2f255-1ff2-48df-b032-63a598f21acd&api=market.PhoneMarket&deviceId=000000000000000&param={"hardware":"sdk","osVersion":8,"deviceName":"sdk","imei":"000000000000000","applicationId":'.$app_self_id.',"resolution":"320x480","type":"appdetail","channel":"ac.publish.m","clientVersion":"0.9.11524","deviceId":"000000000000000","sdkVersion":8}';
        my $downloader = new AMMS::Downloader(
                method=>'POST',
                'content-type' => 'application/x-www-form-urlencoded',
                content=>$content,
                );
        my $response=$downloader->download("http://mobile.appchina.com/market/api");

        return "fail to download appchina meta" unless $downloader->is_success;

        utf8::decode($response);
        if( $response=~ /"description":"(.*?)",/g)
        {
            $app_info->{description}=$1;
            $app_info->{description} =~ s/\\r\\n/<br>/;
        }

        $app_info->{app_name}=$1 if $response=~/"applicationName":"(.*?)",/;
        $app_info->{author}=$1 if $response=~/"devLogin":"(.*?)",/;
        $app_info->{total_install_times}=$1 if $response=~/"downloadCount":(.*?),/;
        $app_info->{last_update}=$1 if $response=~/"lastUpdate":"(.*?)",/;
        $app_info->{official_rating_stars}=$1 if $response=~/"rating":(.*?),/ ;
        $app_info->{official_rating_times}=$1 if $response=~/"ratingCount":(.*?),/ ;
        $app_info->{size}=$1 if $response=~/"size":(.*?),/ ;
        $app_info->{current_version}=$1 if $response=~/"version":"(.*?)",/ ;


#        Encode::_utf8_on($app_info->{official_category});
        if (defined($category_mapping{$app_info->{official_category}})){
            $app_info->{trustgo_category_id}=$category_mapping{$app_info->{official_category}};
        }else{
            my $str="$market:Out of TrustGo category:".$app_info->{app_url_md5};
            open(OUT,">>/root/outofcat.txt");
            print OUT "$str\n";
            close(OUT);
            die "Out of Category";
        }



        @node= $tree->look_down( id=>"related" );
        @tags=$node[0]->find_by_tag_name("a");
        $app_info->{related_app} = [] if scalar @tags;
        foreach(@tags){
            next if not ref $_;
            push @{$app_info->{related_app}}, $url_base.$_->attr("href");
        }

        $app_info->{'apk_url'}="http://www.appchina.com//market/d/$app_self_id/www.berry_0/&http%3A%2F%2Fwww.appchina.com%2Fsoft_detail_${app_self_id}_0_10.html";
        $app_info->{price}=0;

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
    my @kids;

    my ($worker, $hook, $params, $pages) = @_;
    
    my $total_apps= 0;

    eval 
    {
        $tree = HTML::TreeBuilder->new; # empty tree
        $tree->parse($params->{'web_page'});
        
        @node = $tree->look_down( class=>"last" );
        $total_apps=$1 if ref $node[0] and $node[0]->attr("href")=~ /soft_list_\d+_(\d+)/;
        $tree = $tree->delete;
    };
    return 0 if $total_apps==0 ;

    my $index=0;
    do{
        my $url=$params->{'base_url'};
        $url =~ s/(.*?soft_list_\d+_)(\d+)(.*)/$1$index$3/;
        push( @{ $pages }, $url );
        $index+=10;
    }while($index<=$total_apps);
   
    return 1;
}

sub extract_app_from_feeder
{
    my $tree;
    my @node;

    my ($worker, $hook, $params, $apps) = @_;
 
    eval {

        $tree = HTML::TreeBuilder->new; # empty tree
        $tree->parse($params->{'web_page'});
        
        @node = $tree->look_down(class=>"app-title");
        foreach (@node) {
            next unless $_;
            $apps->{$1}="$url_base".$_->attr("href") if $_->attr("href") =~ /soft_detail_(\d+)/;
        }
        $tree = $tree->delete;
    };

    $apps={} if $@;

    return 1;
}
