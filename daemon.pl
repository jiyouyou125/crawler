#!/usr/bin/perl
BEGIN{unshift(@INC, $1) if ($0=~m/(.+)\//);}
use strict;
use warnings;

use AMMS::Util;
use AMMS::Downloader;
use AMMS::AppExtractor;
use File::Basename;

my $exec_command;
my $max_thread_num;
my @thread_array;
my $current_thread_num;


# Deal with the command line...
use Getopt::Std;
use vars qw ($opt_p $opt_m $opt_t $opt_c $opt_h);
getopts ('p:c:t:m:h');

die "\nusage:perl daemon.pl [fmcth] \n" if $opt_h;
die "\nplease check config parameter\n" unless init_gloabl_variable( $opt_c );

@thread_array   =();
$exec_command   ='perl '.$conf->getAttribute('BaseBinDir').'/'.$opt_p;
$max_thread_num =$conf->getAttribute('MaxProcessNum');
$current_thread_num =0;

$db_helper->restore_task( $opt_m, $opt_t);

while(1)
{
    ##search the pid who is not alive, and get rid of it. and fetch one more thread
    #check this crawler's status from server	
    &start_one_job if &check_host_status;
   
    sleep(30);
}

sub start_one_job
{
    my $records=();

    #my $resp=" ps ux |grep Crawler_Main.pl|awk ' {print $2,$9;}'";

    my $resp=`ps ax |grep '$opt_p $opt_t' |grep -v grep -c`;		
    
    $resp=~s/[\r\n]/_n_n/g;
    $current_thread_num =$1 if $resp=~/(\d+)/;

    #check db handler  
    while( not $db_helper->is_connected)
    {
        ##reconnect
        $db_helper->connect_db();
        sleep(5);
    }

	   while(($max_thread_num-$current_thread_num)>0) 
    { 
        my $task_id=$db_helper->get_task($opt_m,$opt_t) or last;
        
        if(($thread_array[$current_thread_num++]=fork()) == 0)##child process
        { 
            my $cmdStr ="$exec_command $opt_t $task_id $opt_c &";

            $logger->info("execute $cmdStr");
            system($cmdStr);

            exit();
        }
        else 
        {
        }
        sleep(1);
    }
	 
	foreach my $pid (@thread_array)
    {
	    next if(!defined($pid));
	          #waitpid($pid,0);
	    wait;
	}
  
    return 1;
}
