package AMMS::Config;

BEGIN{unshift(@INC, $1) if ($0=~m/(.+)\//);}
use strict;
use Config::General;
use Digest::MD5 qw(md5_hex);
use Log::Log4perl;

#####===================
my $singleton;

sub new
{
    my $class   = shift;
    my $conf    = shift;

    return $singleton if defined $singleton;

    $singleton = bless {}, $class;

    return $singleton->initialise( $conf );
}

# read_config()
#
#	Get the initiate  value of the system configurate file default.cfg
# and set it to the global variable
#	Returns value: Null
#
#

sub read_config
{
    my $self        = shift;
    my $conf_file    = shift;
    
    my $config  = Config::General->new(
            -ConfigFile => $conf_file,
            -BackslashEscape => 0,
            -MergeDuplicateBlocks => 1,
            -AutoTrue => 1,
            -InterPolateVars=> 1,
            );

    my %conf= $config->getall;

    return undef unless scalar %conf;
    
    $self->{ 'CONFIG' } = \%conf;

    return 1;
}

sub save_config
{  
    my $self        = shift;
    my $conf_file   = shift;
 
 	unless (scalar ${ $self->{ 'CONFIG' } }  )
    {
    	warn( 'nothing with the config' );
    	return undef;
    }
    
    SaveConfig( $conf_file, $self->{ 'CONFIG' } );
    
    return 1;
}



# getAttribute (value)
#
#	Get the  speciale value of the given field  from the system configurate file default.cfg
# 
#	Returns value: the value of the field
#
#
sub getAttribute
{
    my $self       = shift;
    my $attribute  = shift;

    $self->read_config() unless scalar %{ $self->{ 'CONFIG' } };

    unless ( exists $self->{ 'CONFIG' }->{ $attribute } )
    {
        warn( "unknow attribute $attribute" );
        return undef;
    }

    return $self->{ 'CONFIG' }->{ $attribute };
}


# setAttribute (name,value)
#
#	set the  speciale value of the given field  from the system configurate file default.cfg
# 
#	Returns value: null
#
#

sub setAttribute
{
    my $self   = shift;
    my %attrs  = @_;

    while ( my ( $attribute, $value ) = each( %attrs ) )
    {
        $self->{ 'CONFIG' }->{ $attribute } = $value;
    }
}



sub initialise
{
    my $self        = shift;
    my $conf_file   = shift;
    my $logger;
    my $current_dir = '.'; 
    
    unless (defined $conf_file)
    {
        $current_dir    = $1 if $0=~m/(.+)\//;
        $conf_file      = $current_dir.'/default.cfg';
	}

    return undef unless $self->read_config( $conf_file );		 

    mkdir($self->getAttribute('AppFolder')) unless -e $self->getAttribute('AppFolder');
    mkdir($self->getAttribute('TempFolder')) unless -e $self->getAttribute('TempFolder');
    mkdir($self->getAttribute('DaemonFolder')) unless -e $self->getAttribute('DaemonFolder');
    mkdir($self->getAttribute('LogFolder')) unless -e $self->getAttribute('LogFolder');
    mkdir($self->getAttribute('PackageFolder')) unless -e $self->getAttribute('PackageFolder');
    mkdir($self->getAttribute('SampleFolder')) unless -e $self->getAttribute('SampleFolder');

	   Log::Log4perl::init( $self->getAttribute('BaseBinDir').'/dbi-logger.conf' );

    $logger = Log::Log4perl->get_logger;
    $logger->info( 'initialize configuration successfully' );
    $self->setAttribute('LOGGER',$logger);	

    $self->get_ip();

    return $self;
}


sub get_ip
{
    my $self    = shift;
    my %if_info;
    my ($ip, $interface) = (undef,undef);
  
    local %ENV;
    local $/ = "\n";
    $ENV{'BASH_ENV'} = undef if exists $ENV{'BASH_ENV'} and defined $ENV{'BASH_ENV'};
  
    my ($newpath)  = ('/sbin/ifconfig -a'  =~/(\/\w+)(?:\s\S+)$/) ;
    $ENV{'PATH'} = $newpath;
  
    my @ifconfig = `/sbin/ifconfig -a`;
    foreach my $line (@ifconfig)
    {
        if ( ($line =~/^\s+/) && ($interface) )
        {
          $if_info{$interface} .= $line;
        }
        elsif (($interface) = ($line =~/(^\w+(?:\d)?(?:\:\d)?)/))
        {
          $line =~s/\w+\d(\:)?\s+//;
          $if_info{$interface} = $line;
        }
    }

    foreach my $key (keys %if_info)
    {
        if (my ($ip) = ($if_info{$key} =~/inet (?:addr\:)?(\d+(?:\.\d+){3})/))
        { 
            next if ($ip eq '127.0.0.1'); 
            return $self->setAttribute('host',$ip);	
        }
        else
        { 
            delete $if_info{$key};
        }
    }
        
    $self->setAttribute('host','127.0.0.1');
}


1;


__END__
