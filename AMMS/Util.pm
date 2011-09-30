package AMMS::Util;
BEGIN{unshift(@INC, $1) if ($0=~m/(.+)\//);}

use strict; 
use AMMS::Config;
use AMMS::DBHelper;
use File::Basename;
use base 'Exporter';

BEGIN
{
    use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);
    @ISA        = qw(Exporter);

    # Set up the exports.
    our @EXPORT = qw(
            $conf $db_helper $logger 
            trim ltrim rtrim
            get_app_dir
            execute_cmd
            send_file_to_server
            check_host_status
            init_gloabl_variable
        );
}

#INIT 
#{
#    &init_gloabl_variable;
#}

our $VERSION="1.0";
our $conf;
our $db_helper;
our $logger;

sub init_gloabl_variable
{
    my $conf_file   = shift;
    
    $conf_file ='./default.cfg' unless defined($conf_file);

    $conf       = AMMS::Config->new( $conf_file ) or die "\nPlease check $conf_file\n\n";
    $db_helper  = new AMMS::DBHelper or die "\nFailed to connect DB\n\n";
    $logger     = $conf->getAttribute('LOGGER') or die "\nFaild to get log handle\n\n";

    return 1;
}


sub update_app_apk
{
	my (%column)=@_;
	
	my $DB_Handle=&Crawler::Config::get_configValue("DB_Handle");
	
 	my $sql="update app_apk set ";
    $sql .= "last_visited_time=now() ";
    $sql .= ",app_unique_name='".$column{app_unique_name}."' " if exists $column{app_unique_name};
    $sql .= ",status='".$column{status}."' " if exists $column{status};
    $sql .= ",need_submmit='".$column{need_submmit}."' " if exists $column{need_submmit};
    $sql .= "where app_id=".$column{app_id};
    $DB_Handle->do($sql);
}

sub update_app_info_status
{
	my ($app_id, $status)=@_;
	
	my $DB_Handle=&Crawler::Config::get_configValue("DB_Handle");
	
 	my $sql="update app_info set status='$status' where app_id=$app_id";
    $DB_Handle->do($sql);
}


sub update_app_source_status
{
	my ($app_id, $status)=@_;
	
	my $DB_Handle=&Crawler::Config::get_configValue("DB_Handle");
	
 	my $sql="update app_source set status='$status', last_visited_time=now() where app_id=$app_id";
    $DB_Handle->do($sql);
}

sub get_task 
{
	my ($task_type)=@_;
	
	my $DB_Handle=&Crawler::Config::get_configValue("DB_Handle");
	
 	my $sql="select task_id from crawler_task where task_type='$task_type' and status='undo' order by request_time asc limit 1";
    my $sth=$DB_Handle->prepare($sql);
    $sth->execute();

    return 0 if $sth->rows == 0;
    
    my $task_id = ($sth->fetchrow_array)[0];

    $sql="update crawler_task set ip='".&Crawler::Config::get_ip."', start_time=now(),status='doing' where task_id=$task_id";
    $DB_Handle->do($sql);

    return $task_id;
}


sub update_task
{
    my ($task_id,$status) = @_;
	my $DB_Handle=&Crawler::Config::get_configValue("DB_Handle");

    my $sql="update crawler_task set status='$status' ";
    $sql .= ", done_time=now() " if( lc($status) eq "done" ); 
    $sql .= "where ip='".&Crawler::Config::get_ip."' ";
    $sql .= "and task_id=$task_id " if defined($task_id);

    $DB_Handle->do($sql);
##whether delete task_detail
}

sub restore_task
{
    my $task_type=shift;
	my $DB_Handle=&Crawler::Config::get_configValue("DB_Handle");

    my $sql="update crawler_task set status='undo' ";
    $sql .= "where ip='".&Crawler::Config::get_ip."' and task_type='$task_type' and status='doing' ";

    $DB_Handle->do($sql);

}

sub insert_app_into_apk_list{
    my $app_id=shift;

	my $DB_Handle=&Crawler::Config::get_configValue("DB_Handle");
    my $sql="insert into app_apk set app_id=$app_id, status='undo', last_visited_time=now()";
    $DB_Handle->do($sql);
}


sub get_app_dir{
    my $market  =shift;
    my $md5     =shift;

    my $path;

#$path = $conf->getAttribute('TempFolder').'/';
    $path .= $market.'/';
    my $index = 0;
    while($index<32){
        $path .= substr($md5, $index, 3).'/';
        $index+=3;
    }
    $path .= $md5;

    return $path;
}

sub send_file_to_server{
    my $source_file = shift;
    my $dest_dir    = shift;
    my $conf        = new AMMS::Config;

    my $host        = $conf->getAttribute( 'CenterServer' );
    my $username    = $conf->getAttribute( 'ServerUsername');
    my $app_dir     = $conf->getAttribute( 'AppFolder');
    my $rsh_result  = $conf->getAttribute( 'LogFolder').'/'.$$.'.rsh';
    
#send to server
    return 0 if not execute_cmd("scp -q $source_file $username\@$host:/$dest_dir");
#untar app package
    my $tarfile = basename( $source_file);
    return 0 if not execute_cmd("rsh -l root $host tar xzvfP  $dest_dir/$tarfile -C $app_dir; echo \$? >$rsh_result");
#check the execute result
    open(RSH, $rsh_result);
    my $result  = <RSH>;
    close(RSH);
    unlink($rsh_result);

    chomp($result);
    return $result == 0;
}


sub execute_cmd{

    my $cmd     = shift;
    my $status  = 0;

    $status = 1 if system($cmd) == 0;
    unless ($status == 1)
    {
        local $|=1;
        if ($? == -1) 
        {
            print "failed to execute: $!\n";
        }elsif ($? & 127) 
        {
            printf "child died with signal %d, %s coredump\n",($? & 127),  ($? & 128) ? 'with' : 'without';
        }else 
        {
            printf "child exited with value %d\n", $? >> 8;
        }
    }

    return $status;
}

sub check_host_status
{
    my $resp;
    my $conf    = new AMMS::Config;

#disk space
	   my $cmd="df -Pkha ".$conf->getAttribute("BaseFolder")." |awk '{print \$4}'";
	   chomp($resp=`$cmd`);

	   if($resp=~/(\d+\.*\d*)/)
    {
        $conf->getAttribute('LOGGER')->error("the disk space is less than 5G,please check!!") and return 0 if($1<1);
    }

#network status
=pod
    require Net::Ping;
    my $p = new Net::Ping("icmp", 30, 32);
    my $r = $p->ping($conf->getAttribute("Local_Gateway"));
    $p->close;

    return $r;
=cut
	return 1;
}




# Perl trim function to remove whitespace from the start and end of the string
sub trim($)
{
    my $string = shift;

    $string =~ s/^\s+//;
    $string =~ s/\s+$//;
    return $string;
}
# Left trim function to remove leading whitespace
sub ltrim($)
{
    my $string = shift;

    $string =~ s/^\s+//;
    return $string;
}
# Right trim function to remove trailing whitespace
sub rtrim($)
{
    my $string = shift;

    $string =~ s/\s+$//;
    return $string;
}
1;

__END__
