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

my $market      = 'www.aimi8.com';
my $url_base    = 'http://www.aimi8.com';
my $downloader  = new AMMS::Downloader;

my %category_mapping=(
"\x{7F51}\x{7EDC}\x{6E38}\x{620F}"=>822,
"\x{76CA}\x{667A}\x{4F11}\x{95F2}"=>810,
"\x{52A8}\x{4F5C}\x{5192}\x{9669}"=>800,
"\x{4F53}\x{80B2}\x{7ADE}\x{901F}"=>811,
"\x{89D2}\x{8272}\x{626E}\x{6F14}"=>812,
"\x{98DE}\x{884C}\x{5C04}\x{51FB}"=>821,
"\x{7ECF}\x{8425}\x{7B56}\x{7565}"=>815,
"\x{68CB}\x{724C}\x{5929}\x{5730}"=>803,
"\x{7CFB}\x{7EDF}\x{548C}\x{5DE5}\x{5177}"=>2206,
"\x{751F}\x{6D3B}\x{548C}\x{5176}\x{4ED6}"=>19,
"\x{901A}\x{8BAF}\x{548C}\x{804A}\x{5929}"=>400,
"\x{97F3}\x{4E50}\x{548C}\x{89C6}\x{9891}"=>7,
"\x{4FE1}\x{606F}\x{548C}\x{8D44}\x{8BAF}"=>14,
"\x{91D1}\x{878D}\x{548C}\x{7406}\x{8D22}"=>2,
"\x{5C0F}\x{8BF4}\x{548C}\x{6F2B}\x{753B}"=>113,
"\x{7F51}\x{7EDC}\x{548C}\x{6D4F}\x{89C8}"=>2210,
"\x{793E}\x{533A}\x{548C}\x{4EA4}\x{53CB}"=>18,
"\x{5B66}\x{4E60}\x{548C}\x{5DE5}\x{4F5C}"=>5
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
 
sub extract_page_list
{
#print "extract page list"."\n";
    my $tree;
    my @node;
    my @tag;
	my ($worker, $hook, $params, $pages) = @_;
    my $total_pages = 0;

    eval 
    {
        $tree = HTML::TreeBuilder->new; # empty tree
		$tree->parse($params->{'web_page'});
        @node = $tree->look_down("class", "page_no");
		if(scalar @node){
			@tag = $node[scalar(@node)-1]->find_by_tag_name("a");
			$total_pages =$tag[0]->as_text if scalar(@tag);
		}
        $tree = $tree->delete;
    };
	
	#print $total_pages."\n";
    return 0 if $total_pages==0 ;
#print "TOM add total_pages:".$total_pages."\n";
    for (1..$total_pages) 
    {
        my $url=$params->{'base_url'};
        $url=~s/page=(\d+)/page=$_/;
        push( @{$pages}, $url);
    }
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
        
        @node = $tree->look_down(class=>"applist");
        my @div_tag = $node[0]->look_down("_tag", "div","class","item");
		#print scalar(@div_tag)."\n";
        foreach (@div_tag) {
            my @a_tag = $_->find_by_tag_name("a");
            $apps->{$1}=$url_base.$a_tag[0]->attr("href") if scalar(@a_tag)&& $a_tag[0]->attr("href") =~ /\/app\/(\d+)_.*/;
        }
		my $count = values %{$apps};
		#print "\n".$count."\n";
        $tree = $tree->delete;
    };
	
    $apps={} if $@;
    return 1;
}

sub extract_app_info
{
	my @node;
	my $tree;
	my @appCategory;
	my @appBasicInfoDiv;
	my @appDescriptionDiv;
	my @appRelatedDiv;
	my @appCommentDiv;
	my @appCategoryA;
	my @appIconDiv;
	my @appIconImage;
	my @appPrice;
	my @appBasicInfoTable;
	my @appBasicInfoTr;
	my @appNameTd;
	my @versionAndAuthorTd;
	my @languageAndUpdateDate;
	my @sizeAndInstallTimes;
	my @ScoreNumberAndShare;
	my @scoreLabel;
	my @appScoreSpan;
	my @downloadWayDiv;
	my @twoDimensionCode;
	my @apkUrl;
	my @appDesciptionContentDiv;
	my @appScreenshotsDiv;
	my @related_appA;
	my @appCommentsGroupDiv;
	my @appCommentsTitleDiv;
	my @appComments;
	my @appCommentGroup;
	my @commentAuthor;
	my @commentDate;
	my @commentContent;
	my $size;
	my @appScreenshotContentDiv;
	my @appScreenshotContents;
 	my $self_id;
 	my @screenShots;
	my ($worker, $hook, $webpage, $app_info) = @_;
    eval {
#utf8::decode($webpage);
         $tree = HTML::TreeBuilder->new; # empty tree
        $tree->parse($webpage);
         @node = $tree->look_down("_tag","div","id","appinfo");
		 @appCategory = $tree->look_down("class","sitemap");
         @appBasicInfoDiv= $node[0]->look_down("_tag","div","class","basic_info");
		 @appDescriptionDiv=$node[0]->look_down("_tag","div","class","app_desc");
		 @appRelatedDiv=$node[0]->look_down("_tag","div","class","other");
		 @appCommentDiv=$node[0]->look_down("_tag","div","class","comments");
	 my $self_id=$1 if($app_info->{'app_url'}=~m{/(\d+)_});	
	#begin to extract offical category
		if(scalar @appCategory){
			@appCategoryA=$appCategory[0]->find_by_tag_name("a");
			$app_info->{"official_category"}=$appCategoryA[2]->as_text();
			#$app_info->{"official_sub_category"}=$appCategoryA[2]->as_text();
		}
#warn 'succes' if $app_info->{official_category} =~ /主/;
        use Encode;
                Encode::_utf8_on($app_info->{'official_category'});
            if (defined($category_mapping{$app_info->{'official_category'}})){
                $app_info->{'trustgo_category_id'}=$category_mapping{$app_info->{'official_category'}};
            }else{
                my $str="Out of TrustGo category:".$app_info->{'app_url_md5'};
                open(OUT,">>/root/outofcat.txt");
                print OUT "$str\n";
                close(OUT);
                die "Out of Category";
            }

		#end to extract offical category
		#begin to extract appBasicInfo
		 @appIconDiv=$appBasicInfoDiv[0]->look_down("_tag","div","class","icon");
		 @appIconImage = $appIconDiv[0]->find_by_tag_name('img');
		if($appIconImage[0]->attr("src") =~ m{\.apk}){
 			#$app_info->{'icon'}=$appIconImage[0]->attr("src");		
		}else{
			 $app_info->{'icon'}=$appIconImage[0]->attr("src");
		};
		$app_info->{'min_os_version'}=0;
		 @appPrice=$appIconDiv[0]->find_by_tag_name("span");
		$app_info->{'price'}=$appPrice[0]->as_text();
		$app_info->{'price'}=0 if $appPrice[0]->as_text() =~ /\x{514D}\x{8D39}/;
		@appBasicInfoTable=$appBasicInfoDiv[0]->look_down("_tag","table","class","basic");
		@appBasicInfoTr=$appBasicInfoTable[0]->look_down("_tag","tr");
		 @appNameTd=$appBasicInfoTr[0]->find_by_tag_name("label");
		 @versionAndAuthorTd=$appBasicInfoTr[2]->find_by_tag_name("td");
		 @languageAndUpdateDate=$appBasicInfoTr[3]->find_by_tag_name("td");
		 @sizeAndInstallTimes=$appBasicInfoTr[4]->find_by_tag_name("td");
		 @ScoreNumberAndShare=$appBasicInfoTr[5]->find_by_tag_name("td");
		$app_info->{'app_name'}=$appNameTd[0]->as_text();
		$app_info->{'current_version'}=$1 if $versionAndAuthorTd[0]->as_text =~ /\x{FF1A}(.*)/;
		$app_info->{'author'}=$1 if $versionAndAuthorTd[1]->as_text =~ /\x{FF1A}(.*)/;
		$app_info->{'language'}=$1 if $languageAndUpdateDate[0]->as_text() =~ /\x{FF1A}(.*)/;
		$app_info->{'last_update'}=$1 if $languageAndUpdateDate[1]->as_text() =~ /\x{FF1A}(.*)/;
		$size = $1 if $sizeAndInstallTimes[0]->as_text() =~ /\x{FF1A}(.*)/;
		$size = $1*1024 if( $size =~ s/([\d\.]+)(.*MB.*)/$1/ );#MB to KB
        $size = $1  if( $size =~ s/([\d\.]+)(.*KB.*)/$1/ );#MB to KB
        $app_info->{'size'}=int($size*1024);#Bytes
		$app_info->{'total_install_times'}=$1 if $sizeAndInstallTimes[1]->as_text() =~ /\x{FF1A}(.*)/;
		@scoreLabel = $ScoreNumberAndShare[0]->look_down("id","com_peo");
		$app_info->{'official_rating_times'}=$scoreLabel[0]->as_text();
		 @appScoreSpan=$appBasicInfoDiv[0]->look_down("_tag","span","id","current_score");
		$app_info->{'official_rating_stars'}=$appScoreSpan[0]->as_text();
		@downloadWayDiv = $appBasicInfoDiv[0]->look_down("_tag","div","class","download_way");
		@twoDimensionCode=$downloadWayDiv[0]->look_down("_tag","img","id","qr2");
		$app_info->{'app_qr'}=$url_base.$twoDimensionCode[0]->attr("src");
		@apkUrl=$downloadWayDiv[0]->look_down("_tag","a",sub {$_[0]->attr('href') =~ m{.*\.apk}});
		$app_info->{'apk_url'}=$apkUrl[0]->attr("href");
		#end to extract appBasicInfo
		#begin to extract appDescription
		@appDesciptionContentDiv = $appDescriptionDiv[0]->look_down("_tag","div","class","dsp");
		$app_info->{'description'}=$appDesciptionContentDiv[0]->as_text();
		@appScreenshotsDiv = $appDescriptionDiv[0]->look_down("_tag","div","class","screenshots");
		@appScreenshotContentDiv = $appScreenshotsDiv[0]->look_down("_tag","div","id","rotator_content");
		#@appScreenshotImages = $appScreenshotContentDiv[0]->look_down("_tag","img");
        #if (scalar @appScreenshotImages) {
        #    $app_info->{"screenshot"} = [];
        #    foreach (@appScreenshotImages){
        #        push @{$app_info->{"screenshot"}},$_->attr("src");
        #    }
        #}
		 @appScreenshotContents=split "img:", $webpage;
                if(scalar @appScreenshotContents){
                        foreach my $item(@appScreenshotContents){
                                if($item=~m/\s*"(.*)"\}/){
                                        push @screenShots, $1;
                                }
                        }
                }
                if(scalar @screenShots){
                        $app_info->{'screenshot'} = [];
                        foreach my $screen(@screenShots){
                                if($screen=~m{$self_id}){
                                 push @{$app_info->{"screenshot"}}, $screen;
                                }
                        }
                }

		#end to extract appDescription
		#begin to extract appRelate
		@related_appA= $appRelatedDiv[0]->find_by_tag_name("a");
		$app_info->{related_app} = [] if scalar @related_appA;
		foreach (@related_appA)
		{
			next unless ref $_;
			push @{$app_info->{related_app}},$url_base.$_->attr("href");
		}
		#end to extract appRelate
		#begin to extract appComment
		@appCommentsGroupDiv=$appCommentDiv[0]->look_down("id","comment_group");
		@appCommentsTitleDiv=$appCommentsGroupDiv[0]->look_down("id","user_coms");
		my $userComments =$appCommentsTitleDiv[0]->as_text();
		$app_info->{'user_numbers'}=$& if($userComments=~/(\d+)/);
		@appComments=$appCommentsGroupDiv[0]->look_down("id","comments");
		@appCommentGroup=$appComments[0]->look_down("class","comment_group");
		foreach my $appCommentItem (@appCommentGroup){
			 @commentAuthor=$appCommentItem->look_down("class","usr");
			 @commentDate  =$appCommentItem->look_down("class","tme");
			 @commentContent=$appCommentItem->look_down("class","comment_text");
			push @{$app_info->{'comment_author'}},$commentAuthor[0]->as_text();
			push @{$app_info->{'comment_date'}},$commentDate[0]->as_text();
			push @{$app_info->{'comment_text'}},$commentContent[0]->as_text();
		}
		#end to extract appComment
	};
if($@){
	$app_info->{'status'}="fail";
}else{
	$app_info->{'status'}="success";    
}
return scalar %{$app_info};
}
