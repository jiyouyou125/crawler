package AMMS::AppFinder;
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

use AMMS::Downloader;
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
    'DELAY'             => 'delay between requests (minutes)',
);

my %ATTRIBUTE_DEFAULT = (
    'MARKET'            => 'market.android.com',
    'TASK_TYPE'         => 'new_app',
    'VERBOSE'           => 1,
    'DELAY'             => 1,
);

my %SUPPORTED_HOOKS = (
    'extract_page_list'          => 'extract all app from feeder',
    'extract_app_from_feeder'    => 'extract app from feeder',
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

    my %feeder_id_urls;

    return undef unless $self->required_attributes_set();
    return undef unless $self->required_hooks_set();

#$self->{'MARKET_ID'} = $self->{ 'DB_HELPER' }->get_market_info($self->{'MARKET'})->{'id'};
#$self->{'APP_START_ID'} = $self->{ 'DB_HELPER' }->get_market_info($self->{'MARKET'})->{'app_start_id'};

    return 0 unless $task_id ;

    $self->{'TASK_ID'} = $task_id;

    ##get feed id and url
    %feeder_id_urls = $self->{ 'DB_HELPER' }->get_task_detail( $task_id );

    unless ( scalar %feeder_id_urls)
    {
        $self->finish_task();
        return 1;
    }

    $self->get_app_url( \%feeder_id_urls );  ##get app url from feed

    ##end a task
    $self->finish_task();

    return 1;
}

sub get_app_url
{
    my $self            = shift;
    my $feeder_id_urls  = shift;

    my $downloader  = $self->{ 'DOWNLOADER' };
    my $logger      = $self->{ 'CONFIG_HANDLE' }->getAttribute('LOGGER');
    my $result= {};
    my %params;

    foreach my $id( keys %{ $feeder_id_urls } )
    {
        my @pages;

        $result->{$id}->{ 'status' } = 'fail';
        $downloader->timeout( $self->{'CONFIG_HANDLE'}->getAttribute("WebpageDownloadMaxTime"));
        my $web_page = $downloader->download( $feeder_id_urls->{$id} );
        if( not $downloader->is_success )
        {
            $result->{$id}->{'status'}='invalid' if $downloader->is_not_found;
            $logger->error('fail to download webpage '.$feeder_id_urls->{$id}.',reason:'.$downloader->error_str);
            warn('fail to download webpage '.$feeder_id_urls->{$id}.',reason:'.$downloader->error_str);
            next;
        }

        utf8::decode($web_page);
        $params{'web_page'}=$web_page;
        $params{'base_url'}=$feeder_id_urls->{$id};
        $self->invoke_hook_functions( 'extract_page_list', \%params,\@pages);

        unless (scalar @pages)
        {
            $logger->error('fail to extract sub url from feeder'.$id);
            next;
        }

        foreach my $page ( @pages ) 
        {
            my %apps;
            ##download the page that contains app
            $web_page = $downloader->download( $page );
            if ( not $downloader->is_success )
            {
                if ($downloader->is_not_found) {
                    $self->{'DB_HELPER'}->save_url_from_feeder($id,$page,'invalid');
                } else {
                    $self->{'DB_HELPER'}->save_url_from_feeder($id,$page,'fail');
                }
                next;
            }


            unless ( utf8::decode($web_page)){
                $logger->error("fail to utf8 convert");
            }
            $params{'web_page'}=$web_page;
            $params{'base_url'}=$page;
            $self->invoke_hook_functions( 'extract_app_from_feeder', \%params,\%apps);
            $self->{'DB_HELPER'}->save_app_into_source( $id,$self->{'MARKET'},\%apps);
            $self->{'DB_HELPER'}->save_url_from_feeder($id, $page,'success');
        }
                       
        $result->{$id}->{ 'status' } = 'success';
    }

    $self->{'RESULT'} = $result;
    return 1;
}

sub finish_task
{
    my $self        = shift;

    $self->{ 'DB_HELPER' }->update_feeder( $self->{'RESULT'} );

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

    if ( not exists $self->{ 'HOOKS' }->{ 'extract_page_list' } )
    {
        warn( "You must provide a 'extract_page_list' hook." );
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
    ($self->{ 'DOWNLOADER' }    = new AMMS::Downloader) || return undef;

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
