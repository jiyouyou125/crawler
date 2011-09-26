use strict;

use HTML::TreeBuilder;
use AMMS::Util;
use AMMS::Downloader;
use IO::Handle;
use open ':utf8';
use HTML::Entities;
use utf8;



my %apps;
my $task_type   = $ARGV[0];
my $task_id     = $ARGV[1];
my $conf_file   = $ARGV[2];
my $market      = 'market.android.com';
my $downloader  = new AMMS::Downloader;
my $lang        = "zh_cn";

die "\nplease check config parameter\n" unless init_gloabl_variable($conf_file);
my $db_handle=$db_helper->get_db_handle();
#my $app_main_dir= $conf->getAttribute( 'TempFolder' );
my $app_main_dir= $conf->getAttribute( 'AppFolder' );
my $sql ="replace into google_multi_lang set app_url_md5=?, status=?,en=?, zh_cn=?";
my $sth =$db_handle->prepare($sql);
my $price_sql ="replace into app_price set status='undo',app_url_md5=?, free=?, zh_cn=?";
my $price_sth =$db_handle->prepare($price_sql);



&get_app_url();

while( my($url_md5, $url)=each(%apps) ){
    my %app_info;
    my $price=0;
    my $status='fail';
    my $en_version=1;
    my $zhcn_version=0;
    my $app_dir=$app_main_dir.'/'.get_app_dir($market,$url_md5);
    my $page_file="$app_dir/page/en_us";

    print "start processing $url_md5\n";
    $logger->error("no page when deal with multi-lang $url_md5") and goto over if not -e $page_file;
    open( PAGE, $page_file) or $logger->error("can't open $page_file,$!");
    local $/=undef;
    my $page=<PAGE>;
    close(PAGE);

###the description is pure English??
    $logger->error("fail to extract en_us version $url_md5") and goto over unless extract_app_info($page, \%app_info);
    $price=$app_info{price};
    $app_info{description} =~s/[^\p{Letter}]//g;
    if ($app_info{description}=~ /[^\x{0000}-\x{024F}\p{Common}]/g){
        unlink("$app_dir/description/en_us");
        unlink("$app_dir/header/en_us");
        $en_version=0;
    }

    my $webpage=&download_webpage($url);;
    $logger->error("fail to download for language $lang $url_md5") and goto over unless defined($webpage); 

    $page="$app_dir/page/$lang";
    open( PAGE,">$page");
    print PAGE $webpage;
    close( PAGE );

    ###only save chinese charset
    $logger->error("fail to extract $lang version") and goto over unless extract_app_info($webpage, \%app_info);
    if( is_chinese($app_info{description}) ){
        $page="$app_dir/header/$lang";
        open( HEADER,">$page");
        print HEADER "app_name=".$app_info{app_name}."\n";
        print HEADER "author=".$app_info{author}."\n";
        close( HEADER );

        $page="$app_dir/description/$lang";
        open( DESC,">$page");
        print DESC $app_info{description};
        close( DESC);

        $zhcn_version=1;
    }

    $status='success';
    if( $price eq '0' ){
        $price_sth->execute($url_md5,1,undef);
    }else{
        $price_sth->execute($url_md5,0,$price);
    }

over:
    $sth->execute($url_md5,$status,$en_version,$zhcn_version);
    print "end processing $url_md5\n";
}

$db_helper->update_task_type($task_id,'price','undo');

sub download_webpage{
    my $tree;
    my @node;

    my $url = shift; 

    $downloader->timeout( $conf->getAttribute("WebpageDownloadMaxTime"));
    my $webpage = $downloader->download("$url&hl=$lang");

    return undef unless $downloader->is_success;
    utf8::decode($webpage);


    return $webpage;
}
    
sub extract_app_info
{
    my $tree;
    my @node;
    my @tags;
    my @kids;
    my ($webpage, $app_info) = @_;

    eval {
        $tree = HTML::TreeBuilder->new; # empty tree
        $tree->warn(1);
        $tree->implicit_tags(0);
        $tree->parse($webpage);

        my @nodes = $tree->find_by_attribute('class','doc-metadata-list');
        my @metas = $nodes[0]->content_list;
        @metas = $tree->find_by_attribute('itemprop','name');
        $app_info->{app_name}=$metas[0]->attr('content');
        $app_info->{author}='Unknow';
        $app_info->{author}=$metas[1]->attr('content');
        @metas=$tree->find_by_attribute('itemprop','price');
        $app_info->{price}= $metas[0]->as_text;
        $app_info->{price}= 0 if $metas[0]->as_text =~ /free/i;
        $app_info->{price}= "RMB:$1" if $metas[0]->as_text =~ /￥([\d\.]+)/i;

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
 
        $tree = $tree->delete;
    };

    if( $@){
        $app_info->{status}='fail';
        return 0;
    }

    return scalar %{$app_info};
}

sub get_app_url
{
    my $app_url;
    my $app_url_md5;
 	
    my $sql=qq{select app_url_md5,app_url from app_info where status='success' and app_url_md5 in (select detail_id from task_detail where task_id=$task_id) };
    my $sth=$db_handle->prepare($sql);
    $sth->execute();
    $sth->bind_columns(\$app_url_md5,\$app_url);
    
    $apps{$app_url_md5} = $app_url  while( $sth->fetch );

    return 1;
}


sub is_chinese{
    my $content=shift;

    return 0 if ($content=~/[\x{3040}-\x{309F}]/g
                or $content=~/[\x{30A0}-\x{30FF}]/g
                or $content=~/[\x{31F0}-\x{31FF}]/g
             );                                
     
    return 0 if ($content=~/[\x{3130}-\x{318F}]/g or $content=~/[\x{AC00}-\x{D7A3}]/g);       

    return 1 if ($content=~/[\x{4e00}-\x{9fa5}]/g );

    return 0;
}
exit;
