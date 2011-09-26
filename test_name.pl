#!/usr/bin/perl 
use warnings;
use strict;
use AMMS::Util;

while(<>){

 my($name,$ver) =  &get_app_name_version($_);
 print $name,"--\t--",$ver,"\n";
}
sub get_app_name_version{
    my $content = shift;
    my $app_name;
    my $current_version;
    if($content=~/\./){
        ($app_name,$current_version) = ($content =~/(.*?)[vV]?((?:\d\.)+\d)/);
    }else{
        $app_name = $content;
    }
	$app_name = rtrim($app_name);
    return ($app_name,$current_version);
}
