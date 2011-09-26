#!/usr/bin/perl
BEGIN{unshift(@INC, $1) if ($0=~m/(.+)\//);}
use strict;
use utf8;
use warnings;

use AMMS::Util;
use AMMS::AppFinder;
use AMMS::Downloader;
use AMMS::NewAppExtractor;
use AMMS::UpdatedAppExtractor;

my $task_type   = $ARGV[0];
my $task_id     = $ARGV[1];
my $conf_file   = $ARGV[2];

my $market      = 'www.mumayi.com';
my $url_base    = 'http://www.mumayi.com';
my $downloader  = new AMMS::Downloader;

my %category_mapping=(
        "\x{4E3B}\x{9898}\x{7F8E}\x{5316}"=>1203,
        "\x{7CFB}\x{7EDF}\x{5DE5}\x{5177}"=>22,
        "\x{7F51}\x{7EDC}\x{6D4F}\x{89C8}"=>2210,
        "\x{4FBF}\x{6377}\x{751F}\x{6D3B}"=>19,
        "\x{5F71}\x{97F3}\x{64AD}\x{653E}"=>7,
        "\x{5B89}\x{5168}\x{4FDD}\x{5BC6}"=>23,
        "\x{56FE}\x{4E66}\x{9605}\x{8BFB}"=>1,
        "\x{56FE}\x{5F62}\x{76F8}\x{5173}"=>15,
        "\x{901A}\x{8BAF}\x{589E}\x{5F3A}"=>2209,
        "\x{4FE1}\x{606F}\x{589E}\x{5F3A}"=>2209,
        "\x{804A}\x{5929}\x{5DE5}\x{5177}"=>4,
        "\x{65F6}\x{949F}\x{65E5}\x{7A0B}"=>16,
        "\x{6559}\x{5B66}\x{8BCD}\x{5178}"=>5,
        "\x{7535}\x{5B50}\x{56FE}\x{4E66}"=>1,
        "\x{5176}\x{5B83}\x{5DE5}\x{5177}"=>22,

        "\x{89D2}\x{8272}\x{626E}\x{6F14}"=>812,
        "\x{98DE}\x{884C}\x{5C04}\x{51FB}"=>821,
        "\x{4F53}\x{80B2}\x{7ADE}\x{6280}"=>814,
        "\x{76CA}\x{667A}\x{4F11}\x{95F2}"=>810,
        "\x{7B56}\x{7565}\x{68CB}\x{724C}"=>815,
        "\x{8D5B}\x{8F66}\x{6E38}\x{620F}"=>811,
        "\x{52A8}\x{4F5C}\x{6E38}\x{620F}"=>801,
        "\x{517B}\x{6210}\x{7ECF}\x{8425}"=>816,
        "\x{6A21}\x{62DF}\x{6E38}\x{620F}"=>813,
        "\x{5176}\x{5B83}\x{6E38}\x{620F}"=>8,
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
    my @kids;
    my ($worker, $hook, $webpage, $app_info) = @_;



    eval {
#utf8::decode($webpage);
        $tree = HTML::TreeBuilder->new; # empty tree
        $tree->parse($webpage);
        
        $app_info->{author}="\x{672A}\x{77E5}";

        @node = $tree->look_down(class=>"mainsoft_header");
        @tags= $node[0]->find_by_tag_name("a");
        $app_info->{app_url} = $url_base.$tags[0]->attr('href');
        @tags= $node[0]->find_by_attribute("id","titleInner");
        $app_info->{app_name}=$1 and $app_info->{current_version}=$2 if $tags[0]->as_text() =~/(.*) (V.*)/;

        @node = $tree->look_down(class=>"mainsoft_center");
        @kids = $node[0]->content_list();##div=>a
        my $img=$kids[0]->find_by_tag_name("img");
        $app_info->{icon}=$img->attr("src");

        my @ul_kids=$kids[1]->content_list;##div=>ul
        my @li_kids = $ul_kids[0]->content_list();##ul=>li
        $app_info->{price}=0; #if $li_kids[2]->as_text =~ //; 
#$app_info->{price}=$li_kids[2]->as_text;

        @li_kids = $ul_kids[2]->content_list();##ul=>li
        $app_info->{system_requirement}=$li_kids[1]->as_text;
        my @os_version = $app_info->{system_requirement} =~ /([\d\.]+)/g;
        my @sort_os_version = sort @os_version;
        $app_info->{min_os_version}=$sort_os_version[0];
        $app_info->{max_os_version}=$sort_os_version[$#sort_os_version];

        @li_kids = $ul_kids[3]->content_list();
        $app_info->{resolution}=$li_kids[2]->as_text;

        @li_kids = $ul_kids[4]->content_list();
        $app_info->{last_update}=$li_kids[2]->as_text;

        @li_kids = $ul_kids[5]->content_list();
        my $size = $li_kids[2]->as_text;
        $size = $1*1024 if( $size =~ s/([\d\.]+)(.*MB.*)/$1/ );#MB to KB
        $size = $1  if( $size =~ s/([\d\.]+)(.*KB.*)/$1/ );#MB to KB
        $app_info->{size}=int($size*1024);#Bytes

        @li_kids = $ul_kids[7]->content_list();
        my @span_kids = $ul_kids[7]->find_by_attribute("id","oldscore");
        $app_info->{official_rating_stars}=($span_kids[0]->as_text)/10.0;
        @span_kids = $ul_kids[7]->find_by_attribute("id","peoplenum");
        $app_info->{official_rating_times}= $span_kids[0]->as_text;;

        ##QR code 
        my @node=$tree->look_down('class'=>'img148');
        @kids=$node[0]->find_by_tag_name("img");
        $app_info->{app_qr}=$kids[0]->attr("src"); 
        
        @node = $tree->look_down(class=>"bjy");
        $app_info->{note}=$1 if $node[0]->as_text =~ /-(.*)/; 

        @node = $tree->look_down(class=>"download");
        $app_info->{'apk_url'}= $node[0]->attr("href"); 

        my $app_id = $1 if $app_info->{'apk_url'} =~ /down.mumayi.com\/(\d+)/;
        $app_info->{'total_install_times'}=get_install_times($app_id);

        @node = $tree->look_down(class=>"ubbhtmls");
        @tags = $node[0]->content_list();
        $app_info->{official_category}=$1 if $tags[2] =~ /-(.*)/ ; 

        use Encode;
        if (defined($category_mapping{$app_info->{official_category}})){
            $app_info->{trustgo_category_id}=$category_mapping{$app_info->{official_category}};
        }else{
            my $str="Out of TrustGo category:".$app_info->{app_url_md5};
            open(OUT,">>/root/outofcat.txt");
            print OUT "$str\n";
            close(OUT);
            die "Out of Category";
        }

        if( $webpage =~ /相关应用(.*?)<\/ul>/s){
            my $text=$1;
            my @a_links= $text=~/<a href="(.*?)"/gs;
            $app_info->{related_app} = [] if scalar @a_links;
            foreach(@a_links){
                next unless defined $_;
                push @{$app_info->{related_app}},"http://www.mumayi.com$_";
            }
        }

        if($webpage=~/软件简介<\/h2>(.*?)<span.*?<center>(.+?)<\/center><br\/>/s){
            my $screen_text=$2;
            $app_info->{description} = $1;
            $app_info->{description} =~ s/[\000-\037]//g;
            $app_info->{screenshot} = [];
            while($screen_text=~/src2="(.*?)"/gs){
                push @{$app_info->{screenshot}}, $1;
            }
        }

        if($webpage=~/<div.*?>什么是权限？<\/a>(.+?)<\/div>/s){
            my $permission_text=$1;
            $app_info->{permission} = [];
            push @{$app_info->{permission}}, $1 while( $permission_text=~/<b>(.*)<\/b>/g);
        }

        $tree = $tree->delete;
    };
    $app_info->{status}='success';
    $app_info->{status}='fail' if $@;
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

    eval 
    {
        $tree = HTML::TreeBuilder->new; # empty tree
        $tree->parse($params->{'web_page'});
        
        @node = $tree->look_down(class=>"pagelist");
        @tag = $node[0]->find_by_tag_name("strong");
        $total_pages =$tag[0]->as_text if scalar(@tag);
        $tree = $tree->delete;
    };
    return 0 if $total_pages==0 ;

    for (1..$total_pages) 
    {
        my $url=$params->{'base_url'};
        $url=~s/(.*?)1\.html/$1$_.html/;
        push( @{ $pages }, $url);
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
        
        @node = $tree->look_down(class=>"list_main_center");
        my @li_tag = $node[0]->find_by_tag_name("li");
        foreach (@li_tag) {
            next if not ref $_;
            my @a_tag = $_->find_by_tag_name("a");
            $apps->{$1}=$url_base.$a_tag[0]->attr("href") if scalar(@a_tag) && $a_tag[0]->attr("href") =~ /android-(\d+)/;
        }
        $tree = $tree->delete;
    };

    $apps={} if $@;

    return 1;
}
