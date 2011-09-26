#!/usr/bin/perl 
# /<title>([^<]+)<\/title>/ms
my $str =
'<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
<head id="ctl00_Head1">
    <title>
	        系统工具
			        - 手机游戏- 手机自助交流系统
					    </title>
						        
						    <script type="text/javascript" src="../js/jquery-1.3.2.min.js"></script>
							    <script language="javascript" type="text/javascript" src="../js/function.js"></script>
								    <link href="../css/css.css" rel="stylesheet" type="text/css" /><title>
									
									</title></head>';
if ( $str =~ /<title>([^<]+)<\/title>/s ) {
	print $1,"\n";
    print &get_base_url($1), "\n";
}

sub get_base_url {
    my ($page_title) = @_;
    if ( $page_title =~ /手机游戏/m ) {
        return $url_base . "/game";
    }
    else {
        return $url_base . "/soft";
    }
}
