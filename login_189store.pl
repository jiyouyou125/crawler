#!/usr/bin/perl 
use strict;
use warnings;
use Data::Dumper;
use HTTP::Cookies;
use LWP::UserAgent;
use MIME::Base64;
use Cwd;
use File::Spec;

my $url = "http://www.189store.com/index.php?app=member&act=login";
my $cookie_file = File::Spec->catfile( getcwd(), "189store.cookie" );

my $ua = LWP::UserAgent->new(keep_alive => 1);
$ua->max_redirect(0);
my $cookie_jar = HTTP::Cookies->new( file => $cookie_file );
$cookie_jar->{ignore_discard} = 1;    #if not write to file, add this param;
$ua->agent("Mozilla/5.0 (Windows NT 6.1) AppleWebKit/535.1 (KHTML, like Gecko) Chrome/14.0.835.186");
$ua->cookie_jar($cookie_jar);

my $login_key;
my $has_login;

sub get_login {
    my $res_login = $ua->get(
"http://www.189store.com/index.php?app=ajax&act=getUserInfo&js=1&ReturnURL="
    );
    if ( $res_login->is_success ) {
		if($res_login->content =~ /登出/){
			$has_login = 1;
		}
        if ( $res_login->content =~ /value="?([^"]+)"?>/ ) {
            $login_key = $1;
        }
    }

}

sub post_login {
    my $res_login = $ua->get(
"http://www.189store.com/index.php?app=ajax&act=getUserInfo&js=1&ReturnURL="
    );
    if ( $res_login->is_success ) {
        if ( $res_login->content =~ /value="?([^"]+)"?>/ ) {
            $login_key = $1;
        }
    }
    die "can't get login_key" if not defined($login_key);
    my $res = $ua->post(
        $url,
        [
            user_name => encode_base64( '462655176@qq.com' . $login_key ),
            password  => encode_base64( 'stone801213' . $login_key ),
            is_ajax   => 1,
            ReturnURL => '',
        ]
    );

    if ( $res->status_line =~ /200/ ) {
        print $res->content, "\n";
    }

}
&get_login;
if(!$has_login){
	&post_login;
}
$ua->default_header("Referer","http://www.189store.com/index.php?app=goods&id=99708");
$ua->default_header("Host","www.189store.com");
my $res = $ua->get(
	"http://www.189store.com/index.php?app=download&act=getDownloadUrl&pkgid=142584"
);
if($res->is_success){
    print Dumper($res);
    my $res_a = $ua->get("http://online.189store.com/chat/chatClient/monitor.js?companyID=10005&configID=4&codeType=custom");
    print Dumper($res);
    my $down_url = $res->header("location");
    $res = $ua->get($down_url);

    print Dumper($res);
}
