package AMMS::NewAppExtractor;
require 5.002;
use strict;

use HTTP::Request;
use HTTP::Status;
use HTTP::Date;
use URI::URL;
use IO::File;
use English;
use Encode;
use Encode qw( encode );
use File::Path;
use Digest::MD5 qw(md5_hex);
use open ':utf8';

use AMMS::Config;
use AMMS::DBHelper;
use AMMS::Downloader;
#use AMMS::Util qw(get_app_dir execute_cmd_str send_file_to_server);
use AMMS::Util;

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
    'NEXT_TASK_TYPE'    => 'what type of task to do',
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
    'language_suffix'          => 'support language',
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

    my %apps;
    my %app_result;

    my $logger  = $self->{ 'CONFIG_HANDLE' }->getAttribute('LOGGER');

    $self->{'APP_RESULT'}   = \%app_result;
    $self->{'TASK_ID'}      = $task_id;

    return 0 unless $task_id ;
    return undef unless $self->required_attributes_set();
    return undef unless $self->required_hooks_set();

    $self->invoke_hook_procedures( 'restore-state' );

    ##get app id and url
    %apps = $self->{ 'DB_HELPER' }->get_task_detail( $self->{'TASK_ID'} );
    $self->finish_task( 'success' ) and return 1 unless scalar %apps;

    $self->{'MARKET_INFO'} = $self->{'DB_HELPER'}->get_market_info($self->getAttribute('MARKET'));
    $self->finish_task( 'fail' ) and return 0
        if  not $self->get_app_result( \%apps )  or##get app info and apk info 
            not $self->package_and_send()        or#package and send to center server
            not $self->save_app_result();     ##insert app info and apk into DB 

    ##end a task
    $self->finish_task( 'success' );

    ##delete app data in disk
#    $self->clean_app_data();

    return 1;
}

sub get_app_url
{
    my $self   = shift;
    my %apps;

    %apps = $self->{ 'DB_HELPER' }->get_app_source_url( $self->{'TASK_ID'} );

    return %apps;
}

sub get_app_result
{
    my $self    = shift;
    my $apps    = shift;

    my $app_result  = $self->{ 'APP_RESULT' };
    my $logger      = $self->{ 'CONFIG_HANDLE' }->getAttribute('LOGGER');
    my $downloader  = new AMMS::Downloader;
    my $web_lang;

    $self->invoke_hook_functions('language_suffix',\$web_lang);
    foreach my $md5 ( keys %{ $apps } )
    {
        my $app_page; 
        my %app_info; 
        my %apk_info;

        local $|;
        $|++;
        print "start processing $md5\n";

        $app_result->{ $md5 }->{ 'app_info'} = \%app_info;
        $app_result->{ $md5 }->{ 'apk_info'} = \%apk_info;

        $app_info{ 'status' } = 'fail';
        $apk_info{ 'status' } = 'fail';
        $apk_info{ 'app_url_md5'  } = $md5;
        $app_info{ 'app_url_md5'  } = $md5;
        $app_info{ 'market_id' } = $self->{'MARKET_INFO'}->{'id'};

        ##download app webpage
        $downloader->timeout( $self->{'CONFIG_HANDLE'}->getAttribute("WebpageDownloadMaxTime"));
        $app_page = $downloader->download($apps->{$md5}.$web_lang);

        if( not $downloader->is_success )
        {
            $app_info{'status'} = 'invalid' if $downloader->is_not_found;
            $logger->error('fail to download webpage '.$apps->{$md5}.',reason:'.$downloader->error_str);
            next;
        }

        ##extract app infor from webpage
        utf8::decode($app_page);
        $app_info{ 'app_url'  } = $apps->{$md5};
        $app_info{ 'app_url_md5'  } = $md5;
        $app_info{ 'app_page'  } = $app_page;
        $self->invoke_hook_functions( 'extract_app_info', $app_page,\%app_info );
        unless ( $self->check_app_info(\%app_info) )
        {
            $app_info{'status'} = 'fail';
            $logger->error("fail to extract app info for $md5");
            next;
        }

        ##download icon,screenshot and video
        unless($self->deal_with_app_info( \%app_info )){
            $app_info{'status'} = 'fail';
            next;
        }

        ##download apk if available
        $apk_info{'app_url'} = $app_info{'app_url'};
        $apk_info{'apk_url'} = $app_info{'apk_url'};
        $apk_info{'price'} = $app_info{'price'};
        $apk_info{'size'} = $app_info{'size'};
        $self->invoke_hook_functions('download_app_apk', \%apk_info);

        $app_info{ 'status'  } = 'success';

        print "end processing $md5\n";
    }

    return 1;
}

sub save_app_result
{
    my $self    = shift;

    my $logger  = $self->{'CONFIG_HANDLE'}->getAttribute('LOGGER');

    ##insert app info into table app_info and apk into into app_apk
    $self->{ 'DB_HELPER' }->start_transaction or die "fail to start transaction"; 
    foreach my $md5 ( keys %{ $self->{'APP_RESULT'} } )
    {
        next unless ref $self->{'APP_RESULT'}->{$md5};
        next if $self->{'APP_RESULT'}->{$md5}->{'app_info'}->{'status'} ne 'success'; 
        if( $self->{ 'DB_HELPER' }->insert_app_info($self->{'APP_RESULT'}->{$md5}->{'app_info'}) == 0 || 
            $self->{'DB_HELPER'}->insert_apk_info($self->{'APP_RESULT'}->{$md5}->{'apk_info'}) == 0 )
        {
            $self->{ 'DB_HELPER' }->cancel_transaction ;
            return 0;
        }
    }

    $self->{ 'DB_HELPER' }->end_transaction;
    return 1;
}



sub finish_task
{
    my $self    = shift;
    my $result  = shift;

    my $app_result  = $self->{'APP_RESULT'};

    if( $result eq 'fail' )
    {
        map { $app_result->{$_}->{'app_info'}->{'status'} = 'fail' } keys %{ $app_result };
    }

    $self->{ 'DB_HELPER' }->update_app_source_status( $_,$app_result->{$_}->{'app_info'}->{'status'} ) foreach ( keys %{ $app_result} );

    if( defined $self->{'NEXT_TASK_TYPE'} ){
        $self->{ 'DB_HELPER' }->update_task_type($self->{'TASK_ID'},$self->{'NEXT_TASK_TYPE'},'undo');
    }else{
        $self->{ 'DB_HELPER' }->update_task($self->{'TASK_ID'},'done');
    }

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

#if ( exists $self->{ 'HOOKS' }->{ $hook_name } )
#    {
#    $self->warn( "$hook_fn already exists" );
#	return undef;
#    }
#    else
#    {
	$self->{ 'HOOKS' }->{ $hook_name } = $hook_fn;
#    }

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

    ($self->{ 'CONFIG_HANDLE' } = new AMMS::Config)  || return undef;
    ($self->{ 'DB_HELPER' }     = new AMMS::DBHelper)    || return undef;


    $self->{'TOP_DIR'} = $self->{'CONFIG_HANDLE'}->getAttribute( 'TempFolder' );
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
    my $app_info    = shift;

    my $status;
    my $errstr;
    my $md5         = $app_info->{'app_url_md5'};
    my $downloader  = new AMMS::Downloader;
    my $logger      = $self->{ 'CONFIG_HANDLE' }->getAttribute('LOGGER');

    #create resouce directory
    my $app_dir= $self->{'TOP_DIR'}.'/'.get_app_dir($self->getAttribute('MARKET'),$md5);
    my $app_header_dir=$app_dir.'/header';
    my $app_desc_dir=$app_dir.'/description';
    my $app_page_dir=$app_dir.'/page';
    my $app_res_dir=$app_dir.'/res';
    my $app_res_pic_dir=$app_res_dir.'/pic';
    my $app_res_video_dir=$app_res_dir.'/video';
    eval { 
        rmtree($app_dir) if -e $app_dir;
        mkpath($app_dir);
        mkpath($app_header_dir);
        mkpath($app_page_dir);
        mkpath($app_desc_dir);
        mkpath($app_res_dir);
        mkpath($app_res_pic_dir);
        mkpath($app_res_video_dir);
    };
    if ( $@ )
    {
        $logger->error( "fail to create directory,AppID:$md5,Error:$EVAL_ERROR"); 
        die "fail to create directory,AppID:$md5,Error:$EVAL_ERROR"; 
        return 0 ;
    }

    #save app info to file 
    my $lang=$self->{'MARKET_INFO'}->{'language'};
    open    PAGE,   ">$app_page_dir/$lang";
    print   PAGE    $app_info->{ 'app_page' };
    close   PAGE;

    #app name and author
    open    HEADER, ">$app_header_dir/$lang";
    print   HEADER "app_name=".$app_info->{'app_name'}."\n";;
    Encode::_utf8_on($app_info->{'author'});
    print   HEADER "author=".$app_info->{'author'}."\n";;
    close   HEADER;

    #description file 
    open    DESC,   ">$app_desc_dir/$lang";
    print   DESC    $app_info->{ 'description' };
    close   DESC;

    #save android permission if exist
    if( defined( $app_info->{'permission'} )) {
        open    PERMISSION, ">$app_dir/permission";
        print   PERMISSION "$_\n" foreach ( @{ $app_info->{'permission'} } );
        close   PERMISSION;
    }

    #save what's new
    if( defined( $app_info->{'whatsnew'} )) {
        open    NEW, ">$app_dir/whatsnew";
        print   NEW $app_info->{'whatsnew'};
        close   NEW;
    }


    
    #save related app if exist
    open    RELATED, ">$app_dir/related";
    print   RELATED  "$_\n" foreach ( @{ $app_info->{'related_app'} } );
    close   RELATED;


    #icon file
    $downloader->timeout($self->{ 'CONFIG_HANDLE' }->getAttribute('ImageDownloadMaxTime'));
    $downloader->download_to_disk($app_info->{'icon'},$app_res_dir,'icon');
    $logger->warn( "fail to download icon,AppID:$md5" ) if not $downloader->is_success;

    #screenshot folder
    $status=0;
    foreach( @{ $app_info->{'screenshot'} } )
    {
        next unless defined($_);
        $downloader->download_to_disk($_,$app_res_pic_dir,$status);
        $status+=1 if $downloader->is_success;
    }
    $logger->warn("fail to download screenshot,AppID:$md5") if not $status;

    #video folder
    if ( exists $app_info->{ 'video' } )
    {
        open VIDEO, ">$app_res_video_dir/video";
        print VIDEO $app_info->{ 'video' };
        close VIDEO;
#   $downloader->download_to_disk($app_info->{'video'},$app_res_video_dir,'video');
#        $logger->error( "fail to download video ,AppID:$md5" ) and return 0 if not $downloader->is_success;
    }


    $self->invoke_hook_functions('extra_processing', $app_info);
    return 1;
}

sub package_and_send
{
    my $self        = shift;

    my $status= 1;
    my $app_dir;
    my $market          = $self->getAttribute('MARKET');
    my $app_sample_dir  = $self->{'CONFIG_HANDLE'}->getAttribute('SampleFolder');
    my $tar_file        = $market.'__'.time.'.tgz';
    my $cmd = 'cd '.$self->{'TOP_DIR'}.'; tar -czPf '.$app_sample_dir.'/'.$tar_file;
    my $app_count= 0;
    my $app_param;
    foreach my $md5 ( keys %{ $self->{'APP_RESULT'} } ) 
    {
        next if $self->{'APP_RESULT'}->{$md5}->{'app_info'}->{'status'} ne 'success';
        $app_dir = get_app_dir($market,$md5);
        #generate meta
        next if not $self->generate_meta_file($app_dir,$self->{'APP_RESULT'}->{$md5});
        $app_param .= " $app_dir"; 
        ++$app_count;
    }

    return $status if defined($self->{NEXT_TASK_TYPE});##some market need other steps

    if ( $app_count )
    {
        $cmd .= " $app_param;cd -";
        unless ( execute_cmd($cmd) ) 
        {
            $self->{'CONFIG_HANDLE'}->getAttribute('LOGGER')->error(
                    "fail to tar app for $self->{TASK_ID}"
                    );
            $status = 0;
        }

        if ( $status )
        {
            $status = 0 unless $self->{'DB_HELPER'}->save_package($self->{TASK_ID},$tar_file);
        }
    }


    
    return $status;
}

sub download_app_apk 
{
    my $self    = shift;
    my $hook_name  = shift;
    my $apk_info= shift;

    my $apk_file;
    my $md5 =   $apk_info->{'app_url_md5'};
    my $apk_dir= $self->{'TOP_DIR'}.'/'. get_app_dir( $self->getAttribute('MARKET'),$md5).'/apk';

    my $downloader  = new AMMS::Downloader;

    $downloader->header({Referer=>$apk_info->{'app_url'}});

    if( $apk_info->{price} ne '0' ){
        $apk_info->{'status'}='paid';
        return 1;
    }
    eval { 
        rmtree($apk_dir) if -e $apk_dir;
        mkpath($apk_dir);
    };
    if ( $@ )
    {
        $self->{ 'LOGGER'}->error( sprintf("fail to create directory,App ID:%d,Error: %s",
                                    $md5,$EVAL_ERROR)
                                 );
        $apk_info->{'status'}='fail';
        return 0;
    }

    my $timeout = $self->{'CONFIG_HANDLE'}->getAttribute('ApkDownloadMaxTime');
    $timeout += int($apk_info->{size}/1024) if defined $apk_info->{size};
    $downloader->timeout($timeout);
    $apk_file=$downloader->download_to_disk($apk_info->{'apk_url'},$apk_dir,undef);
    if (!$downloader->is_success)
    {
        $apk_info->{'status'}='fail';
        return 0;
    }

    my $unique_name=md5_hex("$apk_dir/$apk_file")."__".$apk_file;

    rename("$apk_dir/$apk_file","$apk_dir/$unique_name");


    $apk_info->{'status'}='success';
    $apk_info->{'app_unique_name'} = $unique_name;

    return 1;
}



###save disk space
sub clean_app_data
{
    my $self    = shift;

    foreach ( keys %{ $self->{'APP_RESULT'} } )
    {
        my $app_dir= $self->{'TOP_DIR'}.'/'.get_app_dir($self->getAttribute('MARKET'),$_);
        eval {
            rmtree($app_dir) if -e $app_dir;
        };  
       
        print $@ if $@;
    }
}          


sub continue_test
{
    my $self        = shift;
    my $app_info    = shift;

#check update time and software size
    my $hash=$self->{'DB_HELPER'}->get_app_info_from_db($app_info->{'app_url_md5'},'last_update','size','current_version');

    return 1 if str2time($hash->{'last_update'}) ne str2time($app_info->{'last_update'})
        or $hash->{'size'} ne $app_info->{'size'} 
        or $hash->{'current_version'} ne $app_info->{'current_version'}; 

    return 0;
}

##these parameters must have
sub check_app_info{
    my $self        = shift;
    my $app_info    = shift;

    return 0 if( $app_info->{'status'} eq 'fail' );

    return 0 if (not defined $app_info->{'app_name'} 
            or not defined $app_info->{'official_category'}
            or not defined $app_info->{'trustgo_category_id'}
            or not defined $app_info->{'last_update'}
            or not defined $app_info->{'size'}
            or $app_info->{'size'} =~ /[^\d\s]/
#            or not defined $app_info->{'price'} 
            or not defined $app_info->{'current_version'} 
            or not defined $app_info->{'app_url'} 
            or not defined $app_info->{'description'} 
            );

    return 1;
}

sub generate_meta_file
{
    my $self    = shift;
    my $app_dir = shift;
    my $app     = shift;

    my $meta_file =$self->{'TOP_DIR'}."/$app_dir/meta";

    open( META, ">:utf8","$meta_file") or ($logger->error("fail to open $meta_file") and return 0);
    select META;

    my $app_info=$app->{app_info};
    my $apk_info=$app->{apk_info};
    print "app_unique_name=".$app_info->{'app_url_md5'}; 
    print "\napp_name=".$app_info->{'app_name'} if exists $app_info->{'app_name'}; 
    print "\napp_unique_package_name=".$app_info->{'app_unique_package_name'}; 
    print "\nofficial_category=".$app_info->{'official_category'}; 
    print "\nsub_official_category=".$app_info->{'sub_official_category'}; 
    print "\ntrustgo_category=".$app_info->{'trustgo_category_id'}; 
#print "\nauthor=".$app_info->{'author'}; 
    print "\nmarket=".$self->{'MARKET_INFO'}->{'name'}; 
    print "\nsupport_os=android";
    print "\napp_capacity=tablet,phone";
    print "\nos_version=".$app_info->{'min_os_version'}.",".$app_info->{'max_os_version'};
    print "\nofficial_rating=".$app_info->{'official_rating_stars'}; 
    print "\nofficial_rating_times=".$app_info->{'official_rating_times'}; 
    print "\nrelease_date=".$app_info->{'release_date'}; 
    print "\nlast_update=".$app_info->{'last_update'}; 
    print "\nsize=".$app_info->{'size'}; 
    print "\ncurrency=".$app_info->{'currency'} if exists $app_info->{'currency'}; 
    print "\nprice=".$app_info->{'price'}; 
    print "\ncurrent_version=".$app_info->{'current_version'}; 
    print "\ntotal_install_times=".$app_info->{'total_install_times'}; 
    print "\nbuy_link=".$app_info->{'app_url'}; 
    print "\ndownload_link=".$app_info->{'apk_url'} if $app_info->{'apk_url'}=~/^http/i; 
    print "\nwebsite=".$app_info->{'website'}; 
    print "\nsupport_website=".$app_info->{'support_website'}; 
    print "\nlanguage=".$self->{'MARKET_INFO'}->{'language'}; 
    print "\ncopyright =".$app_info->{'copyright '}; 
    print "\nage_rating=".$app_info->{'age_rating'}; 
    print "\n";
    close(META);

    return 1;
}
