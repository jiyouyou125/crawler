#!/usr/bin/perl
BEGIN{unshift(@INC, $1) if ($0=~m/(.+)\//);}
use strict;
use utf8;
use warnings;
use File::Basename;
use File::Spec;
use Digest::MD5 qw/md5_hex/;
use HTML::TreeBuilder;

use AMMS::Util;
use AMMS::AppFinder;
use AMMS::Downloader;
use AMMS::NewAppExtractor;
use AMMS::UpdatedAppExtractor;
use AMMS::DBHelper;
use Data::Dumper;
#require "zol_action.pl";

my $task_type   = $ARGV[0];
my $task_id     = $ARGV[1];
my $conf_file   = $ARGV[2];

my $config = read_config("zol.conf");
my $market = $config->{market};
my $url_base = $config->{url_base};

my $downloader  = new AMMS::Downloader;

my %category = %{$config->{category_mapping}};


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
        
    };
    $app_info->{status}='success';
    $app_info->{status}='fail' if $@;
    return scalar %{$app_info};
}

sub extract_page_list
{

    my ($worker, $hook, $params, $pages) = @_;
    
    my $webpage = $params->{'web_page'};
    my $total_pages = 0;
    eval 
    {
        my $per_page;
        if( $webpage =~ /每页(\d+)款.*?共(\d+)页/){
            $per_page = $1;
            $total_pages = $2;
        }
        if($pager eq "1"){
            $pages = $1 if $params->{base_url} =~ /sub(\d+)/;
        }else{
           if($webpage =~ /page3.*?<a target="_self" href="(.*?)">/){
               my $page_tmp = $1;
               my $page_base = $1 if $page_tmp =~ /(.*?_)\d+\.html/);
                for(1..$total_pages){
                    push @{$pages}, File::Spec->catfile($url_base,$page_base,$_);
                }
            }  
        }
    };
    return 0 if $total_pages==0 ;
   
    return 1;
}

sub extract_app_from_feeder
{
    my $tree;
    my @node;

    my ($worker, $hook, $params, $apps) = @_;
 
    eval {
        my $webpage = $params->{'web_page'};
        $tree = HTML::TreeBuilder->new;
        my $dbh = new AMMS::DBHelper;
        $tree->no_expand_entities(1);
        $tree->parse($webpage);
        my @nodes = $tree->look_down("_tag","dl","class","list_dl clearfix");
        for my $node(@nodes){

           #app_url
           my $a_tag = $node->find_by_tag_name("a"); 
           my $app_url = File::Spec->catfile($url_base,$a_tag->attr("href"));
           $apps->{$1} = $app_url if basename($a_tag->attr("href")) =~ /(\d+)/;
           my $dd_tag = $node->find_by_tag_name("dd");
           my @span_tag = $dd_tag->find_by_tag_name("span");
           my $name_info = $node->find_by_tag_name("a")->as_text;
           my ($app_name,$app_version) = ($name_info =~ //); 
           if(scalar @span_tag){
            #last_update
            $dbh->save_extra_info(md5_hex($app_url),{ last_update => $span_tag[1]->as_text,
                                                      size  => $span_tag[0]->as_text,
                                                      total_install_times=> $span_tag[2]->as_text,
                                                    });
           }
        }
    };

    $apps={} if $@;

    return 1;
}
sub read_config{
    my $file = shift;
    open my $handle,"<:encoding(UTF-8)",$file or 
        die "can't open the file:$file:$!";
    my $content = do{ local $/,<$handle>};
    my $config = eval($content);
    return $config;
}

