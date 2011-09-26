package AMMS::Downloader;
#BEGIN{unshift(@INC, $1) if ($0=~m/(.+)\//);}

use strict; 
use LWP;
use URI;
use File::Basename;
use LWP::MediaTypes qw(guess_media_type media_suffix);
use vars qw/$UA/;

sub new {
    my $proto = shift;
    my $class = (ref ($proto) or $proto);
    my $self = {};
    my $ua;
    my $request;
    my %option=@_;

    $ua = LWP::UserAgent->new();
    $ua->timeout(30);
    $ua->env_proxy;
    $ua->agent("Mozilla/4.0 (compatible; MSIE 8.0; Windows NT 5.1; Trident/4.0; .NET CLR 2.0.50727;");
    $ua->default_header('Accept-Language',"en;q=0.7");
    $request = HTTP::Request->new;
    $request->method("GET");#default
    $request->method($option{method}) if defined($option{method});
    $request->content($option{content}) if defined($option{content});
    $ua->default_header('content-type' =>$option{'content-type'}) if defined($option{'content-type'});

    $self->{RESPONSE} =undef;
    $self->{REQUEST} = $request;
    $self->{USERAGENT} = $UA || $ua;
    $self->{TIMEOUT} = 120;
    $self->{URLRETRIES} = 3; 
    $self->{SUCCESS} = 0; 

    bless $self, $class;

    return $self;
}


sub header{
    my $self = shift;

    foreach my $param_hash (@_) { 
        my ($key, $value)= each(%{$param_hash});
        $self->{USERAGENT}->default_header( $key=>$value);
    }

    return $self->{SUCCESS};

}

sub error_str{
    my $self = shift;

    return $self->{RESPONSE}->status_line;
}

sub is_not_found 
{
    my $self = shift;

    return $self->{RESPONSE}->code == &HTTP::Status::RC_NOT_FOUND;
}

sub is_not_modified
{
    my $self = shift;

    return $self->{RESPONSE}->code == &HTTP::Status::RC_NOT_MODIFIED;
}


sub error_code{
    my $self = shift;

    return $self->{RESPONSE}->code;
}

sub if_modified_since
{
    my $self  = shift;

    $self->{REQUEST}->if_modified_since(shift);
}

sub is_success
{
    my $self = shift;

    if (@_) { 
        $self->{SUCCESS} = shift;
    }

    return $self->{SUCCESS};
}

sub timeout
{
    my $self = shift;

    if (@_) { 
        $self->{TIMEOUT} = shift;
    }

    return $self->{TIMEOUT};
}

sub max_retry_times
{
    my $self = shift;

    if (@_) { 
        $self->{URLRETRIES} = shift;
    }

    return $self->{URLRETRIES};
}

sub download{
    my $self=shift;
    my $url=shift;
    my $response;
    my $try_times=1;

    my $ua = $self->{USERAGENT};
    my $request = $self->{REQUEST};

    $request->uri($url);
    $self->is_success(0); 
    eval{
        local $SIG{ALRM} = sub   {   die "download timeout"};
        alarm $self->timeout;;

        $response = $ua->request($request);
        until($response->is_success){
            ++$try_times;
            last if ( $response->code < 500 );
            last if( $try_times>$self->max_retry_times);
            sleep(30);
            $response = $ua->request($request);
        }
        alarm(0);
    };
    
    alarm(0);

    $self->{RESPONSE}=$response;
    $self->is_success(0) and return undef if $@ =~/download timeout/;
    $self->is_success(1) if $response->is_success;

    return $response->content;
}

sub download_to_disk
{
    my $self = shift;
    my ($url,$dir,$file) = @_;;
    my $filepath;

    my $webpage = $self->download($url); 

    if( $self->is_success){
        if ($webpage =~ /Access to this site is blocked/) {
            $self->is_success(0);
            return undef;
        }
        unless (defined($file)){
            if( defined($self->{RESPONSE}->header("content-disposition")) and
                    $self->{RESPONSE}->header("content-disposition")=~/filename="(.*)"/)
            {
                $file=$1;
            }else{
                $file=basename($self->{RESPONSE}->base);
            }
        }
        $filepath="$dir/$file";
        open( OUTFILE, ">$filepath") or die "Can't open $filepath: $!";
        print OUTFILE $webpage or die "can't write $filepath:$!";
        close(OUTFILE);
        return $file;
    }

    return undef;
}

1;
