#!/usr/bin/perl
BEGIN{unshift(@INC, $1) if ($0=~m/(.+)\//);}
use strict;
use warnings;
use POSIX;
use English; 
use Digest::MD5 qw(md5_hex);

use AMMS::Util;
use AMMS::AppFinder;
use AMMS::Downloader;
use AMMS::NewAppExtractor;
use AMMS::UpdatedAppExtractor;

my $task_type   = $ARGV[0];
my $task_id     = $ARGV[1];
my $conf_file   = $ARGV[2];

my $market      = 'www.amazon.com';
my $url_base    = 'http://www.amazon.com';
my $downloader  = new AMMS::Downloader;
my $dbhelper    = new AMMS::DBHelper;
my $dbh         = $dbhelper->get_db_handle;

my %month_map = (
        "January"=>"1","February"=>"2","March"=>"3","April"=>"4",
        "May"=>"5","June"=>"6","July"=>"7","August"=>"8",
        "September"=>"9","October"=>"10","November"=>"11","December"=>"12"
        );

my %category_mapping= (
        "Books & Comics"=>1,
        "Books & Readers"=>115,
        "Graphic Novels"=>113,
        "Children's Books"=>116,
        "Comic Strips"=>305,
        "Manga"=>306,
        "City Info"=>2101,
        "New York"=>2101,
        "Chicago"=>2101,
        "Boston"=>2101,
        "Philadelphia"=>2101,
        "Los Angeles"=>2101,
        "Communication"=>4,
        "Cooking"=>1905,
        "Education"=>5,
        "Language"=>106,
        "Math"=>109,
        "Reading"=>115,
        "Science"=>102,
        "Test Guides"=>505,
        "Writing"=>506,
        "History"=>105,
        "Entertainment"=>6,
        "Finance"=>2,
        "Accounting"=>207,
        "Banking"=>200,
        "Investing"=>204,
        "Money & Currency"=>208,
        "Personal Finance"=>209,
        "Games"=>8,
        "Action"=>822,
        "Adventure"=>800,
        "Arcade"=>801,
        "Board"=>802,
        "Cards"=>803,
        "Casino"=>804,
        "Casual"=>818,
        "Educational"=>806,
        "Kids"=>808,
        "Multiplayer"=>824,
        "Music"=>809,
        "Puzzles & Trivia"=>816,
        "Racing"=>811,
        "Role Playing"=>812,
        "Sports"=>814,
        "Strategy"=>815,
        "Health & Fitness"=>9,
        "Diet & Weight Loss"=>905,
        "Exercise & Fitness"=>901,
        "Medical"=>10,
        "Sleep Trackers"=>907,
        "Pregnancy"=>908,
        "Meditation"=>909,
        "Kids"=>25,
        "Reading"=>2500,
        "Alphabet"=>2501,
        "Math"=>2502,
        "Science"=>2503,
        "History"=>2504,
        "Language"=>2505,
        "Animals"=>2506,
        "Popular Characters"=>2507,
        "Lifestyle"=>19,
        "Home & Garden"=>1906,
        "Self Improvement"=>1907,
        "Astrology"=>1908,
        "Relationships"=>1909,
        "Hair & Beauty"=>1910,
        "Celebrity"=>1903,
        "Quizzes & Games"=>1911,
        "Advice"=>1912,
        "Parenting"=>1913,
        "Magazines"=>14,
        "Music"=>709,
        "Artists"=>710,
        "Instruments"=>711,
        "Radio"=>712,
        "Songbooks"=>713,
        "Music Players"=>714,
        "Navigation"=>13,
        "News & Weather"=>14,
        "World"=>1402,
        "US"=>14,
        "Business"=>1403,
        "Politics"=>1409,
        "Entertainment"=>1405,
        "Science & Tech"=>1410,
        "Health"=>1411,
        "Weather"=>24,
        "Novelty"=>113,
        "Photography"=>15,
        "Podcasts"=>714,
        "Productivity"=>16,
        "Real Estate"=>205,
        "Reference"=>108,
        "Ringtones"=>1202,
        "Pop"=>1202,
        "Latin"=>1202,
        "Christian"=>1202,
        "Voicetones"=>1202,
        "Comedy"=>1202,
        "Classical"=>1202,
        "Sound Effects"=>1202,
        "Sports"=>1202,
        "Shopping"=>17,
        "Social Networking"=>18,
        "Sports"=>20,
        "Football"=>2003,
        "Baseball"=>2004,
        "Basketball"=>2005,
        "Hockey"=>2006,
        "NCAA"=>2007,
        "Golf"=>2008,
        "UFC"=>2009,
        "Boxing"=>2010,
        "Soccer"=>2011,
        "Tennis"=>2012,
        "Themes"=>1203,
        "Travel"=>21,
        "Flight"=>1304,
        "Hotel"=>2103,
        "Auto Rental"=>2104,
        "Trip Planner"=>2107,
        "Transportation"=>13,
        "Utilities"=>22,
        "Battery Savers"=>2214,
        "Alarms & Clocks"=>2215,
        "Calculators"=>1600,
        "Calendars"=>1605,
        "Notes"=>1608,
        "Web Browsers"=>2210,
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
    my $NewAppExtractor= new AMMS::NewAppExtractor('MARKET'=>$market,'TASK_TYPE'=>$task_type,'NEXT_TASK_TYPE'=>'new_apk');
    $NewAppExtractor->addHook('download_app_apk', \&download_app_apk);
    $NewAppExtractor->addHook('extract_app_info', \&extract_app_info);
    $NewAppExtractor->run($task_id);
}
elsif( $task_type eq 'update_app' )##download updated app info and apk
{
    my $UpdatedAppExtractor= new AMMS::UpdatedAppExtractor('MARKET'=>$market,'TASK_TYPE'=>$task_type,'NEXT_TASK_TYPE'=>'new_apk');
    $UpdatedAppExtractor->addHook('download_app_apk', \&download_app_apk);
    $UpdatedAppExtractor->addHook('extract_app_info', \&extract_app_info);
    $UpdatedAppExtractor->run($task_id);
}

exit;

sub extract_app_info
{
    my $tree;
    my @node;
    my @tags;
    my @kids;
    my ($worker, $hook, $webpage, $app_info) = @_;

    ##what's new
    $webpage =~ s/\n//g;

    if( $webpage =~ m!<div class=bucket>    <h2>Latest Updates</h2>.*?(<li>.*</li>)        </ul>    </div><\/div>!g)
    {
        $app_info->{whatsnew}=$1;
        $app_info->{whatsnew}=~s/<li>//g;
        $app_info->{whatsnew}=~s/<\/li>/<br>/g;
    }

    ##product Details
    $app_info->{apk_url} =$1 if $webpage =~ m!<b>ASIN:</b>\s+(B.*?)</li>!g;
    $app_info->{last_update}="$3-$month_map{$1}-$2" if $webpage =~ m!<b> Date first available at Amazon.com:</b>\s+([\w]+)\s+([\d]+),\s+([\d]+)!;
    $app_info->{age_rating}=$1 if $webpage =~ m!<a id="mas-product-rating-definition" href="javascript:void\(0\);">(.*?)</a>!g;

    ##Product features 
    if( $webpage =~ m!<h2>Product Features</h2>.*?(<li>.*</li>)        </ul>      </div>!g)
    {
        $app_info->{feature}=$1;
        $app_info->{feature}=~s/<li>//g;
        $app_info->{feature}=~s/<\/li>(\cI)*/<br>/g;
    }

    ##Product description 
    if( $webpage =~ m!<div class="h2">Product Description</div>(.*?)</div></div></div></div>!g)
    {
        $app_info->{description}=$1;
        $app_info->{description}=~s/<li>//g;
        $app_info->{description}=~s/<\/li>(\cI)*/<br>/g;
        $app_info->{description}=~s/&#8226;/\x{2022}/g;
        $app_info->{description}=~s/<p>/__p/g;
        $app_info->{description}=~s/<\/p>/___p/g;
        $app_info->{description}=~s/<br>/__br/g;
        $app_info->{description}=~s/<.*?>//ig;
        $app_info->{description}=~s/___p/<\/p>/g;
        $app_info->{description}=~s/__p/<p>/g;
        $app_info->{description}=~s/__br/<br>/g;
    }


    ##Technical Details
    if( $webpage =~ m!<li><b>Size:</b>\s*(\S+)</li>!g)
    {
        my $size=$1;
        $size =$1*1024 if( $size =~ s/([\d\.]+)(.*MB)/$1/ );#MB to KB
        $size =$1  if( $size =~ s/([\d\.]+)(.*KB)/$1/ );#MB to KB
        $app_info->{size}=int($size*1024);#Bytes
    }

    $app_info->{current_version}=$1 if( $webpage =~ m!<li><b>Version:</b>\s*([\d\.]+)</li>!g);
    $app_info->{author}=$1 if( $webpage =~ m!<b>Developed By:</b> (.*?)</li>!g);
    $app_info->{min_os_version}=$1 if( $webpage =~ m!<b>Minimum Operating System:</b> Android ([\d\.]+)</li>!g);

    if( $webpage =~ m!<div id="appPermissions">(.*?)</div>!){
        my $permission=$1;
        $app_info->{permission} = [];
        while($permission=~m!<li>(.*?)</li>!g){
            push @{$app_info->{permission}},$1;
        }
    }

#$webpage =~ m!<span id="btAsinTitle" style="">(.*?)</span>!g;
    $app_info->{app_name}=$1 if($webpage =~ m!<span id="btAsinTitle" style="">(.*?)</span>!);

    $app_info->{official_rating_stars}=0;
    $app_info->{official_rating_times}=0;
    $app_info->{official_rating_stars}=$1 if $webpage =~ m!<span>([\d\.]+) out of 5 stars</span>!g;
    $app_info->{official_rating_times}=$1 if $webpage =~ m!>([\d,]+) customer reviews?</a>\)!;
    $app_info->{official_rating_times}=~s/,//g;
    $app_info->{icon}=$1 if $webpage =~ m!registerImage\("original_image", "(http.*?)",!;
    $app_info->{price}=0;
    $app_info->{price}="USD:$1" if $webpage =~ m!<b class="priceLarge">\$([\d\.]+)</b>!; 
    $app_info->{price}=0 if $app_info->{price}=~/0\.0/;

    ##category from DB
    my $hash_ref=$dbh->selectrow_hashref("select category from app_extra_info where app_url_md5='$app_info->{app_url_md5}'");
    $app_info->{official_category}=$hash_ref->{'category'};
    if (defined($app_info->{official_category}) and defined($category_mapping{$app_info->{official_category}})){
        $app_info->{trustgo_category_id}=$category_mapping{$app_info->{official_category}};
    }else{
        my $str="Out of TrustGo category:".$app_info->{app_url_md5};
        open(OUT,">>/root/outofcat.txt");
        print OUT "$str\n";
        close(OUT);
        $app_info->{status}='fail' if $@;
        warn "Out of Category";
        return 0;
    }

    $app_info->{status}='success';
    return scalar %{$app_info};
}

sub get_install_times
{
    my $app_id=shift;

    my $url      = "http://www.mumayi.com/plus/disdls.php?aid=$app_id";

    my $content = $downloader->download($url);

    return $1 if ( $downloader->is_success and $content =~ /(\d+)/ );

    return 0;
}

sub get_comment_times
{
    my $app_id= shift;

    my $url="http://www.mumayi.com/plus/comment.php?dopost=count&aid=$app_id";

    my $content = $downloader->download($url);

    return $1 if ( $downloader->is_success and $content =~ /(\d+)/ );

    return 0;
}



sub extract_page_list
{
    use File::Basename;

    my $tree;
    my @node;
    my @tag;

    my ($worker, $hook, $params, $pages) = @_;
    
    my $total_pages = 0;
    my $total_apps= 0;

    eval 
    {
        $tree = HTML::TreeBuilder->new; # empty tree
        $tree->parse($params->{'web_page'});
        
        @node = $tree->look_down(class=>"resultCount");
        if ($node[0]->as_text =~ /of\s+([\d,]+)\s+Results/){
            $total_apps = $1;
        }elsif( $node[0]->as_text =~ /Showing\s+([\d,]+)\s+Results?/){
            $total_apps = $1;
        }else{
            warn 'fail to extract page list '.$params->{'base_url'};
            return;
        }
        $total_apps =~s/,//g;
        $total_pages = ceil($total_apps/12);
        $tree = $tree->delete;
    };
    return 0 if $total_pages==0 ;

    for (1..$total_pages) 
    {
        my $url=$params->{'base_url'};
        $url=~s/(.*)1/$1$_/;
        push( @{ $pages }, $url);
    }
   
    return 1;
}

sub extract_app_from_feeder
{
    my $tree;
    my @nodes;

    my ($worker, $hook, $params, $apps) = @_;
 
    my $sql="replace into app_extra_info set app_url_md5=?,category=?";
    my $sth=$dbh->prepare($sql);

    eval {

        $tree = HTML::TreeBuilder->new; # empty tree
        $tree->parse($params->{'web_page'});
        
        my $category = $tree->look_down(_tag=>"div",id=>"bcDiv");
        $category = substr $category->as_text,(rindex $category->as_text, "\x{203A}")+1 ;
        $category = trim($category);
        @nodes = $tree->look_down(class=>"newPrice");
        foreach (@nodes) {
            next if not ref $_;
            my $a_tag = $_->find_by_tag_name("a");
            my $app_url = $a_tag->attr("href") if defined($a_tag);
#$apps->{$1}=$app_url if $app_url=~/\/dp\/(B.*?)\//;
            warn  $params->{base_url} unless defined $app_url;
            if ($app_url=~/(.*?\/dp\/(B.*?))\//){
                $apps->{$2}=$1."?ie=UTF8";
            }else{
                warn  $params->{base_url};
            }

            ##insert category because it can't be got in detail
            my $md5=md5_hex($apps->{$2});
            my $hash_ref=$dbh->selectrow_hashref("select category from app_extra_info where app_url_md5='$md5'");
            if (defined($hash_ref->{category}) 
                    and defined($category_mapping{$hash_ref->{category}})){
                ##it's already a sub category;
                next if $category_mapping{$hash_ref->{category}} >=100;
            }
            $sth->execute($md5,$category);

        }
        $tree = $tree->delete;
    };

    $apps={} if $@;

    return 1;
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

#$app_package_name='';
#    $app_package_name=$1 if $apk_info->{app_url}=~/https:\/\/market.android.com\/details\?id=(.*)/;
#$apk_info->{'apk_url'}=$app_package_name;
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
        $logger->error( sprintf("fail to create directory,App ID:%d,Error:%s",$md5,$EVAL_ERROR) );
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
