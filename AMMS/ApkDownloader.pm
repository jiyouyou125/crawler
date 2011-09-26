package MAMS::AppExtractor;
require 5.002;
use strict;

use HTTP::Request;
use HTTP::Status;
use HTML::TreeBuilder 3.03;
use URI::URL;
use LWP::RobotUA 1.171;
use IO::File;
use English;
use Encode qw( encode );
use File::Path;
use Digest::MD5 qw(md5_hex);
use open ':utf8';

use MAMS::Config;
use MAMS::DBHelper;
use MAMS::Downloader;
use MAMS::Util qw(get_app_magic_dir execute_cmd send_file_to_server);

#------------------------------------------------------------------------------
#
# Public Global Variables
#
#------------------------------------------------------------------------------

use vars qw( $VERSION );
$VERSION = '0.001';

#------------------------------------------------------------------------------
#
# Private Global Variables
#
#------------------------------------------------------------------------------

my %ATTRIBUTES = (
    'NAME'              => 'Name of the AppExtractor',
    'VERSION'           => 'Version of the AppExtractor, N.NNN',
    'VERBOSE'           => 'boolean flag for verbose reporting',
    'MARKET'            => 'which android makrt to be crawled',
    'TASK_TYPE'         => 'what type of task this AppExtractor to do, new app or check app',
    'DELAY'             => 'delay between requests (minutes)',
);

my %ATTRIBUTE_DEFAULT = (
    'MARKET'            => 'market.android.com',
    'TASK_TYPE'         => 'new_app',
    'VERBOSE'           => 1,
    'DELAY'             => 1,
);

my %SUPPORTED_HOOKS = (
    'extract_app_info'          => 'extract all app info from app webpage',
    'download_app_apk'          => 'download app apk',
#    'continue-test'             => 'return true if should continue iterating',
#    'modified-since'            => 'returns modified-since time for URL passed',
);

my %HOOKS_DEFAULT = (
    'download_app_apk'          => \&download_app_apk,
);



sub new
{
    my $class    = shift;
    my %options  = @ARG;

    # The two argument version of bless() enables correct subclassing.
    # See the "perlbot" and "perlmod" documentation in perl distribution.

    my $object = bless {}, $class;

    return $object->initialise( \%options );
}


sub run
{
    my $self      = shift;
    my $task_id   = shift;

    my %app_id_urls;
    my %app_result;

    my $logger  = $self->{ 'CONFIG_HANDLE' }->getAttribute('LOGGER');

    $self->{'APP_RESULT'}   = \%app_result;
    $self->{'TASK_ID'}      = $task_id;

    return 0 unless $task_id ;
    return undef unless $self->required_attributes_set();
    return undef unless $self->required_hooks_set();

    $self->invoke_hook_procedures( 'restore-state' );

    ##get app id and url
    %app_id_urls = $self->get_url();
    $self->finish_task( 'success' ) and return 1 unless scalar %app_id_urls;

    $self->finish_task( 'fail' ) and return 0
        if  not $self->get_app_result( \%app_id_urls )  or##get app info and apk info 
            not $self->package_and_send()           or#package and send to center server
            not $self->save_app_result();     ##insert app info and apk into DB 

    ##end a task
    $self->finish_task( 'success' );

    ##delete app data in disk
    $self->clean_app_data();

    return 1;
}

sub get_url
{
    my $self   = shift;
    my %app_id_urls;

    if ( $self->{TASK_TYPE} eq 'new_app' )
    {
        %app_id_urls = $self->{ 'DB_HELPER' }->get_app_source_url( $self->{'TASK_ID'} );
    }
    elsif ( $self->{TASK_TYPE} eq 'updated_app' )
    {
        %app_id_urls = $self->{ 'DB_HELPER' }->get_app_info_url( $self->{'TASK_ID'} );
    }
    else
    {
        %app_id_urls = ();
    }

    return %app_id_urls;
}

sub get_app_result
{
    my $self        = shift;
    my $app_id_urls = shift;

    my $downloader  = $self->{ 'DOWNLOADER' };
    my $app_result  = $self->{ 'APP_RESULT' };
    my $logger      = $self->{ 'CONFIG_HANDLE' }->getAttribute('LOGGER');

    foreach my $app_id ( keys %{ $app_id_urls } )
    {
        my $app_page; 
        my %apk_info; 
        my %app_info; 

        ##download app webpage
        $app_result->{$app_id}->{ 'status' } = 'fail';
        $downloader->timeout( $self->{'CONFIG_HANDLE'}->getAttribute("WebpageDownloadMaxTime"));
        $app_page = $downloader->download($app_id_urls->{$app_id});

        if( not $downloader->is_success )
        {
            $app_result->{$app_id}->{ 'status' } = 'invalid' if $downloader->is_not_found;
            $logger->error('fail to download webpage '.$app_id_urls->{$app_id}.',reason:'.$downloader->error_str);
            next;
        }

        ##extract app infor from webpage
        utf8::decode($app_page);
        $self->invoke_hook_functions( 'extract_app_info', \$app_page,\%app_info );
        unless ( scalar %app_info )
        {
            $logger->error("fail to extract app info for $app_id");
            next;
        }

        next if $self->invoke_hook_functions( 'continue_test', \%app_info );

        ##download icon,screenshot and video
        next if not $self->deal_with_app_info( $app_id, \%app_info );

        ##download apk if available
        ( $apk_info{'status'}, $apk_info{'app_unique_name'} ) =
            $self->invoke_hook_functions('download_app_apk',$app_info{'apk_url'});

        $apk_info{'apk_url'} = $app_info{'apk_url'};

        $app_result->{ $app_id }->{ 'status' } = 'success';
        $app_result->{ $app_id }->{ 'app_info'} = \%app_info;
        $app_result->{ $app_id }->{ 'apk_info'} = \%apk_info;
    }

    return 1;
}

sub save_app_result
{
    my $self        = shift;

    my $logger    = $self->{'CONFIG_HANDLE'}->getAttribute('LOGGER');

    ##insert app info into table app_info and apk into into app_apk
    $self->{ 'DB_HELPER' }->start_transaction or die "fail to start transaction"; 
    if ( not $self->{ 'DB_HELPER' }->save_app_info($self->{'APP_RESULT'}) or 
         not $self->{ 'DB_HELPER' }->savet_apk_info($self->{'APP_RESULT'}) 
        )
    {
        $self->{ 'DB_HELPER' }->cancel_transaction;
        $logger->error("fail to insert app info for ".$self->{'TASK_ID'} );
        return 0;
    }
    $self->{ 'DB_HELPER' }->end_transaction;

    return 1;
}



sub finish_task
{
    my $self        = shift;
    my $result      = shift;
    my $app_result  = shift;

    if( $result eq 'fail' )
    {
        $app_result->{$_}='fail'  foreach (keys %{ $app_result });
    }

    $self->{ 'DB_HELPER' }->update_app_source_status( $app_result ) 
        if $self->{'TASK_TYPE'} eq 'new_app';

    $self->{ 'DB_HELPER' }->update_task($self->{'TASK_ID'},'done');

    return 1;
}

#------------------------------------------------------------------------------

=head2 setAttribute

  $AppExtractor->setAttribute( ... attribute-value-pairs ... );

Change the value of one or more AppExtractor attributes.  Attributes are identified
using a string, and take scalar values.  For example, to specify the name of
your AppExtractor, you set the C<NAME> attribute:

   $AppExtractor->setAttribute( 'NAME' => 'WebStud' );

The supported attributes for the AppExtractor module are listed below, in the I<AppExtractor
ATTRIBUTES> section.

=cut

#------------------------------------------------------------------------------

sub setAttribute
{
    my $self   = shift;
    my %attrs  = @ARG;

    while ( my ( $attribute, $value ) = each( %attrs ) )
    {
        unless ( exists $ATTRIBUTES{ $attribute } )
	{
	    $self->warn( "unknown attribute $attribute - ignoring it." );
	    next;
	}
        $self->{ $attribute } = $value;
    }
}

#------------------------------------------------------------------------------

=head2 getAttribute

  $value = $AppExtractor->getAttribute( 'attribute-name' );

Queries a AppExtractor for the value of an attribute.  For example, to query the
version number of your AppExtractor, you would get the C<VERSION> attribute:

   $version = $AppExtractor->getAttribute( 'VERSION' );

The supported attributes for the AppExtractor module are listed below, in the I<AppExtractor
ATTRIBUTES> section.

=cut

#------------------------------------------------------------------------------

sub getAttribute
{
    my $self       = shift;
    my $attribute  = shift;

    unless ( exists $ATTRIBUTES{ $attribute } )
    {
	$self->warn( "unknown attribute $attribute" );
	return undef;
    }

    return $self->{ $attribute };
}



=head2 addHook

  $AppExtractor->addHook( $hook_name, \&hook_function );
  
  sub hook_function { ... }

Register a I<hook> function which should be invoked by the AppExtractor at a specific
point in the control flow. There are a number of I<hook points> in the AppExtractor,
which are identified by a string.  For a list of hook points, see the
B<SUPPORTED HOOKS> section below.

If you provide more than one function for a particular hook, then the hook
functions will be invoked in the order they were added.  I.e. the first hook
function called will be the first hook function you added.

=cut

#------------------------------------------------------------------------------

sub addHook
{
    my $self       = shift;
    my $hook_name  = shift;
    my $hook_fn    = shift;

    if ( not exists $SUPPORTED_HOOKS{ $hook_name } )
    {
	$self->warn( <<WARNING );
Unknown hook name $hook_name; Ignoring it!
WARNING
	return undef;
    }

    if ( ref( $hook_fn ) ne 'CODE' )
    {
	$self->warn( <<WARNING );
$hook_fn is not a function reference; Ignoring it
WARNING
	return undef;
    }

    if ( exists $self->{ 'HOOKS' }->{ $hook_name } )
    {
    $self->warn( "$hook_fn already exists" );
	return undef;
    }
    else
    {
	$self->{ 'HOOKS' }->{ $hook_name } = $hook_fn;
    }

    return 1;
}

#------------------------------------------------------------------------------

=head2 proxy, no_proxy, env_proxy

These are convenience functions are setting proxy information on the
User agent being used to make the requests.

    $AppExtractor->proxy( protocol, proxy );

Used to specify a proxy for the given scheme.
The protocol argument can be a reference to a list of protocols.

    $AppExtractor->no_proxy(domain1, ... domainN);

Specifies that proxies should not be used for the specified
domains or hosts.

    $AppExtractor->env_proxy();

Load proxy settings from I<protocol>B<_proxy> environment variables:
C<ftp_proxy>, C<http_proxy>, C<no_proxy>, etc.

=cut

#------------------------------------------------------------------------------

sub proxy
{
    my $self  = shift;
    my @argv  = @ARG;

    return $self->{ 'AGENT' }->proxy( @argv );
}

sub no_proxy
{
    my $self  = shift;
    my @argv  = @ARG;

    return $self->{ 'AGENT' }->no_proxy( @argv );
}

sub env_proxy
{
    my $self  = shift;

    return $self->{ 'AGENT' }->env_proxy();
}

#==============================================================================
#
# Private Methods
#
#==============================================================================

#------------------------------------------------------------------------------
#
# required_attributes_set - check that the required attributes have been set
#
#------------------------------------------------------------------------------

sub required_attributes_set
{
    my $self = shift;

    $self->verbose( "Check that the required attributes are set ...\n" );
    my $status = 1;

    for ( qw( MARKET TASK_TYPE ) )
    {
        if ( not defined $self->{ $_ } )
        {
            $self->warn( "You haven't set the $_ attribute" );
            $status = 0;
        }
    }

#$self->{ 'AGENT' }->from( $self->{ 'EMAIL' } );
#    $self->{ 'AGENT' }->agent( $self->{ 'NAME' } . '/' . $self->{ 'VERSION' } );
#    $self->{ 'AGENT' }->delay( $self->{ 'DELAY' } )
#        if defined( $self->{ 'DELAY' } );

    return $status;
}

#------------------------------------------------------------------------------
#
# required_hooks_set - check that the required hooks have been set
#
#------------------------------------------------------------------------------

sub required_hooks_set
{
    my $self = shift;

    $self->verbose( "Check that the required hooks are set ...\n" );

    if ( not exists $self->{ 'HOOKS' }->{ 'extract_app_info' } )
    {
        $self->warn( "You must provide a 'extract_app_info' hook." );
        return 0;
    }

    return 1;
}



#------------------------------------------------------------------------------
#
# initialise() - initialise global variables, contents, tables, etc
#       $self   - the AppExtractor object being initialised
#       @options - a LIST of (attribute, value) pairs, used to specify
#               initial values for AppExtractor attributes.
#       RETURNS    undef if we failed for some reason, non-zero for success.
#
# Initialise the AppExtractor, setting various attributes, and creating the
# User Agent which is used to make requests.
#
#------------------------------------------------------------------------------

sub initialise
{
    my $self     = shift;
    my $options  = shift;

    my $attribute;

    # set attributes which are passed as arguments
    
    foreach $attribute ( keys %$options )
    {
        $self->setAttribute( $attribute, $options->{ $attribute } );
    }

    # set those attributes which have a default value,
    # and which weren't set on creation.

    foreach $attribute ( keys %ATTRIBUTE_DEFAULT )
    {
        if ( not exists $self->{ $attribute } )
        {
            $self->{ $attribute } = $ATTRIBUTE_DEFAULT{ $attribute };
        }
    }

    # set those hooks which have a default value,
    # and which weren't set on creation.

    foreach my $hook_name ( keys %HOOKS_DEFAULT)
    {
        $self->{ 'HOOKS' }->{ $hook_name } = $HOOKS_DEFAULT{ $hook_name };
    }

    ($self->{ 'CONFIG_HANDLE' } = new MAMS::Config)  || return undef;
    ($self->{ 'DB_HELPER' }     = new MAMS::DBHelper)    || return undef;
    ($self->{ 'DOWNLOADER' }    = new MAMS::Downloader) || return undef;


    return $self;
}

#------------------------------------------------------------------------------
#
# invoke_hook_procedures() - invoke a specific set of hook procedures
#	$self      - the object for the AppExtractor we're invoking hooks on
#	$hook_name - a string identifying the hook functions to invoke
#	@argv      - zero or more arguments which are passed to hook function
#
# This is used to invoke hooks which do not return any value.
#
#------------------------------------------------------------------------------

sub invoke_hook_procedures
{
    my $self       = shift;
    my $hook_name  = shift;
    my @argv       = @ARG;

    return unless exists $self->{ 'HOOKS' }->{ $hook_name };
    foreach my $hookfn ( @{ $self->{ 'HOOKS' }->{ $hook_name } } )
    {
	&$hookfn( $self, $hook_name, @argv );
    }
    return;
}

#------------------------------------------------------------------------------
#
# invoke_hook_functions() - invoke a specific set of hook functions
#	$self     - the object for the AppExtractor we're invoking hooks on
#	$hook_name - a string identifying the hook functions to invoke
#	@argv      - zero or more arguments which are passed to hook function
#
# This is used to invoke hooks which return a success/failure value.
# If there is more than one function for the hook, we OR the results
# together, so that if one passes, the hook is deemed to have passed.
#
#------------------------------------------------------------------------------

sub invoke_hook_functions
{
    my $self       = shift;
    my $hook_name  = shift;
    my @argv       = @ARG;

    my $result     = 0;

    return $result unless exists $self->{ 'HOOKS' }->{ $hook_name };

    my $hookfn = $self->{ 'HOOKS' }->{ $hook_name };

	return &$hookfn( $self, $hook_name, @argv );
}

#------------------------------------------------------------------------------
#
# verbose() - display a reporting message if we're in verbose mode
#	$self  - the AppExtractor object
#	@lines - a LIST of one or more strings, which are print'ed to
#		 standard error output (STDERR) if VERBOSE attribute has
#		 been set on the AppExtractor.
#
#------------------------------------------------------------------------------

sub verbose
{
    my $self   = shift;

    print STDERR @ARG if $self->{ 'VERBOSE' };
}

#------------------------------------------------------------------------------
#
# warn() - our own warning routine, generate standard format warnings
#
#------------------------------------------------------------------------------

sub warn
{
    my $self  = shift;
    my @lines = shift;

    my $me = ref $self;

    print STDERR "$me: ", shift @lines, "\n";
    foreach my $line ( @lines )
    {
        print STDERR ' ' x ( length( $me ) + 2 ), $line, "\n";
    }
}

sub deal_with_app_info
{
    my $self        = shift;
    my $app_id      = shift;
    my $app_info    = shift;

    my $status;
    my $errstr;
    my $downloader= $self->{ 'DOWNLOADER' };
    my $logger    = $self->{ 'CONFIG_HANDLE' }->getAttribute('LOGGER');

    #create resouce directory
    my $app_magic_dir = get_app_magic_dir($app_id);
    my $app_main_dir=$self->{ 'CONFIG_HANDLE'}->getAttribute( 'TempFolder' ).'/'.
                     $self->getAttribute( 'MARKET' ).'/'.
                     $app_magic_dir.'/'.$app_id;
    my $app_res_dir=$app_main_dir.'/res';
    my $app_res_pic_dir=$app_res_dir.'/pic';
    my $app_res_video_dir=$app_res_dir.'/video';
    eval { 
        rmtree($app_main_dir) if -e $app_main_dir;
        mkpath($app_main_dir);
        mkpath($app_res_dir);
        mkpath($app_res_pic_dir);
        mkpath($app_res_video_dir);
    };
    if ( $@ )
    {
        $logger->error( "fail to create directory,AppID:$app_id,Error:$EVAL_ERROR"); 
        die "fail to create directory,AppID:$app_id,Error:$EVAL_ERROR"; 
        return 0 ;
    }

    #description file 
    open    DESC,   ">$app_main_dir/description";
    print   DESC    $app_info->{ 'description' };
    close   DESC;

    #icon file
    $downloader->timeout($self->{ 'CONFIG_HANDLE' }->getAttribute('ImageDownloadMaxTime'));
    $downloader->download_to_disk($app_info->{'icon'},$app_res_dir,'icon');
    $logger->info( "fail to download icon,AppID:$app_id" ) and return 0 if not $downloader->is_success;

    #screenshot folder
    $status=1;
    foreach( @{ $app_info->{'screenshot'} } )
    {
        $downloader->download_to_disk($_,$app_res_pic_dir);
        $status=0 and last if not $downloader->is_success;
    }
    $logger->error("fail to download screenshot,AppID:$app_id") and return 0 if not $status;

    #video folder
    if ( exists $app_info->{ 'video' } )
    {
        $downloader->download_to_disk($app_info->{'video'},$app_res_video_dir,'video');
        $logger->error( "fail to download video ,AppID:$app_id" ) and return 0 if not $downloader->is_success;
    }

    return 1;
}

sub download_app_apk 
{
    my $self    = shift;
    my $app_id  = shift;
    my $apk_url = shift;

    my $apk_file;
    my $apk_dir =$self->{ 'CONFIG_HANDLE'}->getAttribute( 'TempFolder' ).'/'.
                     $self->getAttribute('MARKET').'/'.
                     get_app_magic_dir($app_id).'/'.$app_id.'/apk';
    my $downloader= $self->{ 'DOWNLOADER' };

    eval { 
        rmtree($apk_dir) if -e $apk_dir;
        mkpath($apk_dir);
    };
    if ( $@ )
    {
        $self->{ 'LOGGER'}->error( sprintf("fail to create directory,App ID:%d,Error: %s",
                                    $app_id,$EVAL_ERROR)
                                 );
        return (undef,'') ;
    }

    $downloader->timeout($self->{'CONFIG_HANDLE'}->getAttribute('ApkDownloadMaxTime'));
    $apk_file=$downloader->download_to_disk($apk_url,$apk_dir,undef);
    return (undef,'') if !$downloader->is_success;

    my $unique_name=md5_hex("$apk_dir/$apk_file")."__".$apk_file;

    rename("$apk_dir/$apk_file","$apk_dir/$unique_name");

    return ('success',$unique_name);
}

sub package_and_send
{
    my $self        = shift;
    my $status      = 0;
    my $app_magic_dir;
    my $current_path    = `pwd`;
    my $market          = $self->getAttribute('MARKET');
    my $app_temp_dir    = $self->{'CONFIG_HANDLE'}->getAttribute( 'TempFolder' );
    my $app_sample_dir  = $self->{'CONFIG_HANDLE'}->getAttribute('SampleFolder');
    my $tarfile         = $app_sample_dir.'/'.$market.'__'.time.'.tgz';
    my $cmd             = qq/cd $app_temp_dir; tar -cf $tarfile/;

    foreach my $app_id ( keys %{ $self->{'APP_RESULT'} } ) 
    {
        next if $self->{'APP_RESULT'}->{$app_id}->{'status'} ne 'success';
        $app_magic_dir = get_app_magic_dir($app_id);
        $cmd .= qq{ $market/$app_magic_dir/$app_id};
        $status = 1;
    }

    if ( $status )
    {
        if (  not execute_cmd($cmd)  or  
             not send_file_to_server($tarfile,
                    $self->{'CONFIG_HANDLE'}->getAttribute('SampleFolder'))
             )
        {
            $self->{'CONFIG_HANDLE'}->getAttribute('LOGGER')->error(
                    "fail to upload pacakge to center server"
                    );
            $status = 0;
        }
    }

    rmtree($tarfile) if -e $tarfile;

    system( "cd $current_path" );

    return $status;
}

###save disk space
sub clean_app_data
{
    my $self    = shift;
    my @apps    = @_;

    my $market          = $self->getAttribute('MARKET');
    my $app_temp_dir    = $self->{'CONFIG_HANDLE'}->getAttribute( 'TempFolder' );
    my $app_sample_dir  = $self->{'CONFIG_HANDLE'}->getAttribute('SampleFolder');
 

    foreach ( keys %{ $self->{'APP_RESULT'} } )
    {
        my $app_dir="$app_temp_dir/$market/".get_app_magic_dir( $_ )."/$_";
                                                        
        eval {
            rmtree($app_dir) if -e $app_dir;
        };  
       
        print $@ if $@;
    }
}          
