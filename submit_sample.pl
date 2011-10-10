#download url
BEGIN{unshift(@INC, $1) if ($0=~m/(.+)\//); $| = 1; }

use strict; 
use Data::Dumper;				
use AMMS::Util;
					
my $market;
my $conf_file="./default.cfg" unless defined($ARGV[0]);

die "\nplease check config parameter\n" unless init_gloabl_variable( $conf_file );

my $sample_dir=$conf->getAttribute('SampleFolder');
my $dbh=$db_helper->get_db_handle;

my $analytic_dir="/mnt/tslab";
my $cloud_dir="/mnt/cloud";

#submit the app to analyzer
while(1)
{
    #check db handler  
    while( not $db_helper->is_connected)
    {
        ##reconnect
        $db_helper->connect_db();
        sleep(5);
    }

    &run_one_time();

    sleep(600);			# check the task every 10 minutes
}
 

sub run_one_time
{
    my $sql="select package_name, task_id from package where (status='undo' or status='fail') and worker_ip='".$conf->getAttribute('host')."' order by insert_time asc";
    my $sth=$dbh->prepare($sql);
    
    $sth->execute;

    warn "no package needed to submit\n" if($sth->rows==0);

    my $status;
    my $tarfile;
    my $tarfile;
    my $hash;
    while( $hash=$sth->fetchrow_hashref)
    {
        $status='success'; 
        $tarfile="$sample_dir/$hash->{package_name}";
        if( -e $tarfile ){
#my $cmd="cp $tarfile $analytic_dir/; cp $tarfile $cloud_dir/; cp $tarfile /mnt/bakup/market";
            my $cmd=" cp $tarfile $cloud_dir/; cp $tarfile /mnt/bakup/market";
#$status='fail' and next unless &replace_old_app($tarfile);#save  local copy
            $status='fail' and next unless &execute_cmd($cmd);
            open(FH,">$tarfile.ready") or die "Can't create $tarfile ready file: $!";
            close(FH);
            #$cmd="cp $tarfile.ready $analytic_dir/;cp $tarfile.ready $cloud_dir/";
            $cmd="cp $tarfile.ready $cloud_dir/";
            $status='fail' and next unless &execute_cmd($cmd);
        }
    }continue{
        if ($status eq 'success'){
            unlink($tarfile);           
        }else{
            #unlink("$analytic_dir/$hash->{package_name}");           
            unlink("$cloud_dir/$hash->{package_name}");           
            #unlink("$analytic_dir/".$hash->{package_name}.".ready");           
            unlink("$cloud_dir/".$hash->{package_name}.".ready");           
        }
        unlink("$tarfile.ready");
        $dbh->do("update package set status='$status',end_time=now() where task_id=$hash->{task_id}");
    }

}

sub replace_old_app{
    my $tarfile = shift;

    my $resp=`tar -tvf  $tarfile  |grep "^d"|awk '{if(\$6 !~ /res|apk|header|page|description/) print \$6}'`;
    $resp=~s/\n/  /g;
    my $cmd="cd ".$conf->getAttribute("TempFolder").";rm -rf $resp";
    return 0 unless execute_cmd($cmd);
    $cmd="cd ".$conf->getAttribute("AppFolder").";rm -rf $resp";
    return 0 unless execute_cmd($cmd);
    $cmd="tar xzvf $tarfile -C ".$conf->getAttribute("AppFolder");
    return execute_cmd($cmd);
}
