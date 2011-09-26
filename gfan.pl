#!/usr/bin/perl
BEGIN{unshift(@INC, $1) if ($0=~m/(.+)\//);}
use strict;
use warnings;

use utf8;
use POSIX qw(strftime);
use Encode;
use Digest::MD5 qw(md5 md5_hex md5_base64);
use File::Basename;
use LWP::UserAgent;
use AMMS::Util;
use AMMS::AppFinder;
use AMMS::Downloader;
use AMMS::NewAppExtractor;
use AMMS::UpdatedAppExtractor;

use open ":utf8", ":std";
#use open ":encoding(gbk)", ":std";

my $base_url = "http://apk.gfan.com/";
my $url = "http://apk.gfan.com/Product/App1471.html";
my $cate_url = 'http://apk.gfan.com/Aspx/UserApp/softpotal.aspx?softCategory=7&i=2';


my $task_type   = $ARGV[0];
my $task_id     = $ARGV[1];
my $conf_file   = $ARGV[2];

my $market      = 'www.gfan.com';
my $url_base    = 'http://www.gfan.com';
my $downloader  = new AMMS::Downloader;

my %category_mapping=(    
	"\x{5F71}\x{97F3}\x{64AD}\x{653E}"         =>         707,           
	"\x{751F}\x{6D3B}\x{5A31}\x{4E50}"         =>         19,            
	"\x{804A}\x{5929}\x{793E}\x{533A}"         =>         400,           
	"\x{901A}\x{8BDD}\x{901A}\x{4FE1}"         =>         4,             
	"\x{91D1}\x{878D}\x{7406}\x{8D22}"         =>         2,             
	"\x{4F53}\x{80B2}\x{7ADE}\x{6280}"         =>         20,            
	"\x{7535}\x{5B50}\x{529E}\x{516C}"         =>         16,            
	"\x{8D44}\x{8BAF}\x{65B0}\x{95FB}"         =>         14,            
	"\x{4EA4}\x{901A}\x{5BFC}\x{822A}"         =>         13,            
	"\x{62CD}\x{7167}\x{6444}\x{5F71}"         =>         15,            
	"\x{7CFB}\x{7EDF}\x{5DE5}\x{5177}"         =>         2206,          
	"\x{7A97}\x{53E3}\x{5C0F}\x{90E8}\x{4EF6}" =>         206,            
	"\x{5B9E}\x{7528}\x{5DE5}\x{5177}"         =>         22,            
	"\x{4E8B}\x{52A1}\x{7BA1}\x{7406}"         =>         16,            
	"\x{6559}\x{80B2}\x{9605}\x{8BFB}"         =>         5,             
	"\x{5065}\x{5EB7}\x{533B}\x{7597}"         =>         10,            
	"\x{4E3B}\x{9898}\x{684C}\x{9762}"         =>         1203,          
	"\x{8BCD}\x{5178}\x{7FFB}\x{8BD1}"         =>         103,           
	"\x{6D4F}\x{89C8}\x{5668}"                 =>          2210,        
	"\x{5B89}\x{5168}\x{9632}\x{62A4}"         =>         23,            
	"\x{8F93}\x{5165}\x{6CD5}"                 =>          2214,        
	"\x{7F51}\x{7EDC}\x{8D2D}\x{7269}"         =>         1700,          
	"\x{4F11}\x{95F2}"                         =>           8,         
	"\x{76CA}\x{667A}"                         =>           810,       
	"\x{89D2}\x{8272}\x{626E}\x{6F14}"         =>         812,           
	"\x{6218}\x{7565}"                         =>           815,       
	"\x{52A8}\x{4F5C}"                         =>           823,       
	"\x{5C04}\x{51FB}"                         =>           821,       
	"\x{7ECF}\x{8425}"                         =>           0,       
	"\x{517B}\x{6210}"                         =>           824,       
	"\x{5192}\x{9669}"                         =>           800,       
	"\x{7F51}\x{6E38}"                         =>           822,       
	"\x{68CB}\x{724C}"                         =>           803,       
	"\x{6A21}\x{62DF}\x{5668}"                 =>          813 ,        
	"\x{4F53}\x{80B2}"                         =>           814,       
	"aHome\x{4E3B}\x{9898}"                    =>           1203,      
	"\x{5C0F}\x{8BF4}"                         =>           301,       
	"\x{7B11}\x{8BDD}"                         =>           303,       
	"\x{8D44}\x{6599}"                         =>           1,     
);



die "\nplease check config parameter\n" unless init_gloabl_variable( $conf_file );

if( $task_type eq 'find_app' ) {  ##find new android app
    my $AppFinder   = new AMMS::AppFinder('MARKET'=>$market,'TASK_TYPE'=>$task_type);
    $AppFinder->addHook('extract_page_list', \&extract_page_list);
    $AppFinder->addHook('extract_app_from_feeder', \&extract_app_from_feeder);
    $AppFinder->run($task_id);
}
elsif( $task_type eq 'new_app' ) {##download new app info and apk
    my $NewAppExtractor= new AMMS::NewAppExtractor('MARKET'=>$market,'TASK_TYPE'=>$task_type);
    $NewAppExtractor->addHook('extract_app_info', \&extract_app_info);
    $NewAppExtractor->run($task_id);
}
elsif( $task_type eq 'update_app' ) {##download updated app info and apk
    my $UpdatedAppExtractor= new AMMS::UpdatedAppExtractor('MARKET'=>$market,'TASK_TYPE'=>$task_type);
    $UpdatedAppExtractor->addHook('extract_app_info', \&extract_app_info);
    $UpdatedAppExtractor->run($task_id);
}

exit;

#my $html_content = responeshtmContent($url);
#print $html_content;

#main();
#sub main {
#	my %app_info;
#	my $html_content = responeshtmContent($url);
#	my (%data, %app, @pages);
##	$data{'web_page'} = responeshtmContent($cate_url);
#
##	$data{'web_page'} = responeshtmContent($cate_url);
##	extract_page_list(0, 0, \%data, \@pages);
#	
##	print $html_content;
#	extract_app_info(0, 0, $html_content, \%app_info);
##   extract_app_from_feeder(0, 0, \%data, \%app);  
#}
#
#sub responeshtmContent {
#	my $pageurl = shift;
#	my $html_browser = LWP::UserAgent->new;
#	$html_browser->timeout(20); #	print "response html $pageurl, please waiting...\n";
#	my $html_response = $html_browser->get($pageurl);
#	my $page = $html_response->decoded_content;#
#	Encode::is_utf8($page);
#	return $page;
#}

sub extract_app_info {
	my ($worker, $hook, $webpage, $app_info) = @_;
	my $url_id_tag               = 'hidPid';
	my $ApkUrl_tag               = 'hidDownApkUrl';
	my $icon_tag                 = 'i icon';
	my $ProductDetail1_imgB      = 'ProductDetail1_imgB';	#二维码
	my $app_name_tag             = 'app_name';
	my ($price_tag_en, $price_tag_cn)               = ('i i1', '价格');	   #'\x{4EF7}\x{683C}');
	my $price_free = "免费";
	my ($author_tag_en, $author_tag_cn)             = ('i i2', '作者');	   #'\x{4F5C}\x{8005}');	
	my ($last_update_tag_en, $last_update_tag_cn)   = ('i i3', '更新时间');	   #'\x{66F4}\x{65B0}\x{65F6}\x{95F4}');
	my ($size_tag_en, $size_tag_cn)                 = ('i i5', '大小');	   # '\x{5927}\x{5C0F}');
	my ($os_tag_en, $os_tag_cn)                     = ('i i6', '支持OS');      #'\x{652F}\x{6301}OS');
	my $description_tag     = 'intro';
	my $scree_shot_tag      = 'imgouter';
	my $category_tag = '<div class="box box671 ml12">';
	my ($tag0, $tag1, $tag2, $tag3, $tag4, $tag5, $tag6, $tag7) = ('div', 'class', 'name', 'id', 'content', 'value', 'src', 'img');
    my (@scree_shot_url, $count);


#   $webpage =~ s/\n//g;
#   $webpage =~ tr/\000-\037/ /;
	#Encode::is_utf8($webpage);
#utf8::encode($webpage);
#	Encode::is_utf8($webpage);
	if ($webpage =~/[$tag1|$tag2|$tag3]="$description_tag">(.*?)<\/div>/s) {
		$app_info->{description} = $1;
		$app_info->{description} =~s/\s{2,}//g;
	}

        if ($webpage =~/$tag1="$icon_tag"(.+)/) {
             ($app_info->{icon}) = ($1 =~ /$tag6="(.+?)"/);
        }
    	
        my ($app_id) = ($app_info->{app_url} =~/app(\d+)/i);
    	$app_info->{total_install_times} = getInstallTimes($app_id);

	if ($webpage =~/$tag3="$ApkUrl_tag"(?:.+)$tag5="(.+?)"/) { #OK   need to call download sub
#		my $apk_html_content = responeshtmContent("$base_url$1");
        my $apk_html_content = $downloader->download("$base_url$1");
#<script>javascript:window.location='http://down.apk.gfan.com/asdf/Pfiles/2011/8/1471_8bfe1531-c190-4bd9-b00d-de5dd64b77f2.apk';</script></form>
		($app_info->{apk_url}) = ($apk_html_content =~/'(.*\.apk)'/);
#		print $app_info->{apk_url};
	}
	if ($webpage =~ /$price_tag_cn(.+)/) {	# OK
		$app_info->{price} = $1; 
		$app_info->{price} =~s/<.+?>//g;
		$app_info->{price} =~s/：//g;
	
		if ( $app_info->{price} =~ /$price_free/ ) {
                     $app_info->{price} = '0';
                 }
                 else {
                     $app_info->{price} =~s/[^\d]//g;
		     if ( ($app_info->{price} eq '') or (not defined $app_info->{price}) ) {
		         $app_info->{price} = '0';
		     }
		     else {    
                         $app_info->{price} = 'gfan: ' . $app_info->{price};
		     }
                 }
                # print $app_info->{price};
	}
	if ($webpage =~ /$tag1="$app_name_tag">(.+)/) { #OK
		my $temp = $1;
        	$temp =~s/<.+?>/ /g; 
        	$temp =~s/\s+$//g; 
		($app_info->{app_name}, $app_info->{current_version}) = (split(/ /, $temp))[0, 1];
		 $app_info->{current_version} =~s/Ver\x{FF1A}//g;	
	} 	
	if ($webpage =~ /$author_tag_cn(.+)/) { #OK
		$app_info->{author} = $1; 
		$app_info->{author} =~s/<(.+?)>//g;
		$app_info->{author} =~s/：//g;
	}
	if ($webpage =~ /$last_update_tag_cn(.+)/) {  
		$app_info->{last_update} = $1;
		$app_info->{last_update} =~s/<.+?>//g;
		$app_info->{last_update} =~s/：//g;
	}

	if ($webpage =~ /$size_tag_en(.+)/ or $webpage =~/$size_tag_cn(.+)/) {	
		$app_info->{size} = $1; 
		$app_info->{size} =~s/<.+?>//g;
		$app_info->{size} =~s/,//g;
		$app_info->{size} =~s/：//g;
		$app_info->{size} =~s/[^\d\.KkMm]//g;
		$app_info->{size} =~s/(.+)MB?/sprintf("%d", $1*1024*1024)/ie;
		$app_info->{size} =~s/(.+)KB?/sprintf("%d", $1*1024)/ie;
		#print $app_info->{size};
	}

    if ($webpage =~ /$os_tag_cn(.+)/) {
		my $temp = $1;
		$temp =~s/<.+?>//g;
		$app_info->{min_os_version}=$1 if $temp =~/([\d\.]+)/;
#		print "$app_info->{min_os_version}, $app_info->{max_os_version}, $app_info->{system_requirement}";
	}
   
	if ($webpage =~/$tag3="$ProductDetail1_imgB"(.+)/) {    #OK
	    ($app_info->{app_qr}) = ($1 =~/$tag6="(.+)"/);
	    #print $app_info->{app_qr};
	}

    $count = 0;                                    
    while ($webpage =~/$tag1="$scree_shot_tag"(.+)/g) {    #OK
	($scree_shot_url[$count++]) = ($1 =~/img src="(.+?)"/);
    }
    pop @scree_shot_url if (@scree_shot_url);	
    $app_info->{screenshot} = \@scree_shot_url;
#	print "@scree_shot_url, \n$count\n";

    if ($webpage =~/$category_tag(.+?)<\/$tag0>/s) {  #OK
        my $temp = $1;
        $temp =~s/\r\n//g;
        $temp =~s/\n//g;
        $temp =~s/<.+?>//g;
        $temp =~s/\s//g;
        $temp =~s/\(.*?\)//g;
        $app_info->{official_category} = (split(/>/, $temp))[-1];
        #print $app_info->{official_category};
    }

    if ( $webpage =~/<$tag0\s+$tag1="score i"(.+)/ ) {		        
	my ($score_value) = ($1 =~ /"score_inner\s(.+?)"/);   #"        
	$app_info->{official_rating_stars} = 0;
	$app_info->{official_rating_stars} = $1/2.0 if defined($score_value) and $score_value=~/(\d+)/;
    }

    my $hidCid = $1 if ( $webpage =~/hidCid(.+)/ );
    $hidCid =~s/[^\d]//g;
    my $xml_url = "http://apk.gfan.com/xml/c$hidCid.xml";
    my $xml_content = $downloader->download($xml_url);
    if ( $downloader->is_success ) {
        while ( $xml_content =~ /<id>(\d+)<\/id>/g ) {
	    my $related_url = $base_url . "Product/App" . $1 . ".html";
            push @{$app_info->{related_app}}, $related_url;
        }
    }


#    use Encode;
    #    Encode::_utf8_on($app_info->{official_category});
    if (defined($category_mapping{$app_info->{official_category}})){
        $app_info->{trustgo_category_id}=$category_mapping{$app_info->{official_category}};
    }else{
        my $str="Out of TrustGo category:".$app_info->{app_url_md5};
        open(OUT,">>/root/outofcat.txt");
        print OUT "$str\n";
        close(OUT);
        return "Out of Category";
    }

    foreach my $key (keys %$app_info) {
	$app_info->{$key} =~s/(\cM|\cJ|\cI)//g;
    }

    $app_info->{status}='success';
    return scalar %{$app_info};

}

sub extract_page_list {
###  How to get $base_page?

    my ($worker, $hook, $params, $pages) = @_;
    my $base_page           = 'http://apk.gfan.com/Aspx/UserApp/';
    my $page_end_tag_cn     = '末页';			#	'\x{672B}\x{9875}';
    my $page_next_tag_cn    = '下一页';			#	'\x{4E0B}\x{4E00}\x{9875}';
    my $tag1                = '<a href';
    my $tag2                = 'title';
    my $current_tag         = 'CurrPage';
    my ($total_pages, $page_url);

#    http://apk.gfan.com/Aspx/UserApp/softpotal.aspx?softCategory=7&i=2
#    http://apk.gfan.com/Aspx/UserApp/softpotal.aspx?softCategory=7&orderBy=DownNum&CurrPage=3&i=2
#    title="末页"
    #Encode::is_utf8($params->{'web_page'});
    $page_url = $1 if ( $params->{'web_page'} =~ /$page_next_tag_cn(.+)$page_end_tag_cn/ );
    
    return 0 if ( not defined $page_url );
    $page_url = $1 if ( $page_url =~ /$tag1="(.+?)"/);
    
    $total_pages = $1 if ( $page_url =~ /$current_tag=(\d{1,3})/ );
    
    foreach my $p (1..$total_pages) {
        $page_url =~s/($current_tag=)\d{1,3}/$1$p/;
#        print "$base_page$page_url\n";
        push( @{ $pages }, "$base_page$page_url");
    }

    return 1;

}

sub extract_app_from_feeder {
    my ($worker, $hook, $params, $apps) = @_;
    my $tag0 = 'class';     
    my $tag1 = 'clearfix';
    my $tag2 = '<li><a href';
    my $tag3 = '<a href';
    my $tag4 = 'title';
    
#    Encode::is_utf8($params->{'web_page'});
#   <li><a href="./Details/App1471.html" title="手机QQ">   <div class="clearfix">   class="clearfix"
    if ( $params->{'web_page'} =~ /$tag0="$tag1"(.+?)$tag0="$tag1"/s ) {
        my $content = $1;
        while ( $content =~/$tag3(.+?)$tag0="$tag4"/g ) {
#            print "$1\n\n";
           my ($apk_url_id) = ($1 =~/$tag3='(.+?)'/);
           $apps->{$1} = $base_url . $apk_url_id if ($apk_url_id =~/(\d+)/);
#           print $apps->{$1}, "\n";
        }
    }
    
    return 1; 
    
}

sub getInstallTimes {    
    my $app_id = shift;    
    my $date_time = strftime( "%a %d %b %Y %H:%M:%S %Z", localtime());    
    my ($wday, $day, $mon, $year, $now) = split(/ /, $date_time);    
    my ($hour, $min, $sec) = split(/:/, $now);
    my $install_url = "http://apk.gfan.com/Product/DataDeal.aspx?act=dnum&d=$wday%20$mon%20$day%20$year%20%3A$min%3A$sec%20GMT+0800&pid=$app_id";

    my ($install_times) = ($downloader->download($install_url) =~ /(\d+)/);
    if (defined $install_times) {        
        return $install_times;    
    }    
    else {        
        return 0;
    }
}

    
sub getCommentMark {    
    my $app_star_width = shift;    
    my $tt = $app_star_width;

    return 0 if ( not defined $app_star_width );
    return 0 if ( $app_star_width eq '0'); 
    $app_star_width =~s/[^\d]//g;

#    my $css_url = $base_url . '/css/style.css';
    
#    my $css_content = $downloader->download($css_url);
    
#    my $score_tag = 'score';    
    my %width;

#    if ( $css_content =~ /\.score\s+\.s\d/ ) {    
         #     print $&, "\n";        
#        while ( $css_content =~/\.(s\d+)\{(.+?)\}/g ) {            
#            my $key = $1; my $value = $2;            
#            ($width{$key}) = ( $value =~ /(\d+)/ );        
#        }    
#    }
    
    my @list = ('0', '7', '16', '25', '32', '43', '48', '61', '67', '79', '86'); 
    if ( not exists $width{1} ) { 
        foreach my $k ( 1..10 ) { 
	    $width{$k} = $list[$k];
 	}   
    }
    
    my $value; 
    eval { $value = sprintf("%0.2f", (($width{$app_star_width} * 5)/$width{'10'})); };
    if (not defined $value) {return 0; }
    return $value;

}
=pod
sub getRelatedApp {
    my $hidCid = shift;
    return 0 if ( not defined $hidCid ); 
    my $xml_url = "http://apk.gfan.com/xml/c$hidCid.xml";
    my $xml_content = $downloader->download($xml_url);
    if ( $downloader->is_success ) {
        while ( $xml_content =~ /<id>(\d+)<\/id>/g ) {
            push @{$app_info->{related_app}},
	    print $base_url, "Product/App", $1, ".html", "\n";
        }
    }
    else {
        return 0;
    }
}
=cut
=pod
$app_info->{app_url}
$app_info->{app_name}
$app_info->{icon}                                        ?
$app_info->{price}                                                      
$app_info->{current_version}
$app_info->{min_os_version}
$app_info->{max_os_version}
$app_info->{resolution}                                  null                 
$app_info->{last_update}
$app_info->{size}
$app_info->{official_rating_stars}                       ?  HOW
$app_info->{app_qr}
$app_info->{note}                                        null
$app_info->{apk_url}
$app_info->{total_install_times}	#get_install_times   ?  not the same
$app_info->{description}                                    
$app_info->{screenshot}                                  array ref
$app_info->{official_rating_times}  # get_comment_times  ?  how?  
$app_info->{official_category}                           ?  
$app_info->{official_sub_category}                         
release_date
visited_times
updated_times
system_requirement
=cut
