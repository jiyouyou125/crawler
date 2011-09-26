BEGIN{unshift(@INC, $1) if ($0=~m/(.+)\//);}

use strict;
use warnings;

use Data::Dumper;				
use AMMS::Util;
					
my $market;
my @markets_be_monitored = @ARGV;
my $conf_file="./default.cfg";

die "\nplease check config parameter\n" unless init_gloabl_variable( $conf_file );

my $dbh=$db_helper->get_db_handle;
my $app_entity_count=$conf->getAttribute("AppEntityCount");
my $apk_entity_count=$conf->getAttribute("ApkEntityCount");
my $app_update_interval=$conf->getAttribute("AppUpdateInterval");
my $app_discovery_interval=$conf->getAttribute("AppDiscoveryInterval");

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

    foreach ( @markets_be_monitored)
    {
        $market=$db_helper->get_market_info($_);
        print localtime()." start to generate task for $market->{name}\n";
        &task_for_find_app;
        &task_for_find_app_again;
        &task_for_updated_app();
        &task_for_new_app();
        &update_market_monitor;
#        &task_for_new_apk();
        print localtime(). " end to generate task for $market->{name}\n";
    }

    sleep(10*60);			# check the task every 10 minutes
}

    
sub task_for_find_app
{		
    my $sql = 'select SQL_BUFFER_RESULT feeder_id, feeder_url from feeder '.
            ' where status="undo" and market_id='.$market->{'id'}.
            ' order by last_visited_time, feeder_id';  
    my $sth = $dbh->prepare($sql);
    $sth->execute();

    my $count=0;
    my %feeder_hash=();
    my $entity_of_task = $market->{'feeder_entity_of_task'};
    while(my $hash=$sth->fetchrow_hashref)
    {
        ++$count;
        $feeder_hash{$hash->{'feeder_id'}}=$hash->{feeder_url};
        next if( $count < $entity_of_task);
        &create_task("feeder","find_app", \%feeder_hash);
        %feeder_hash=();
        $count=0;
    }
    $sth->finish();
    
    &create_task("feeder","find_app", \%feeder_hash) if (scalar keys %feeder_hash>0 && $count>0);

}

sub task_for_find_app_again
{		
    #check if the update circle is done, if no, wait until it's done.
    my $sql = "select SQL_BUFFER_RESULT feeder_id,feeder_url from feeder ".
            " where market_id=$market->{'id'}".
            " and (status='success' or status='fail')".
            " and TIMESTAMPDIFF( MINUTE,last_visited_time, now() )/60 >$market->{interval_of_discovery}".
            ' order by last_visited_time, feeder_id';  
    my $sth = $dbh->prepare($sql);
    $sth->execute();

    my $count=0;
    my %feeder_hash=();
    my $entity_of_task = $market->{'feeder_entity_of_task'};
    while(my $hash=$sth->fetchrow_hashref)
    {
        ++$count;
        $feeder_hash{$hash->{'feeder_id'}}=$hash->{'feeder_url'};
        next if( $count < $entity_of_task );
        &create_task("feeder","find_app", \%feeder_hash);
        %feeder_hash=();
        $count=0;
    }
    $sth->finish();
    
    &create_task("feeder","find_app", \%feeder_hash) if (scalar keys %feeder_hash>0 && $count>0);
}



sub task_for_new_apk 
{		
    my @app_arr=();
    my $count=0;
    my $app_id;
    
    my $sql = "select SQL_BUFFER_RESULT app_id from app_apk where status='undo' order by last_visited_time, app_id";  
    my $sth = $dbh->prepare($sql);
    $sth->execute();

    while(my $hash=$sth->fetchrow_hashref)
    {
        $app_id=$hash->{app_id};					
        push @app_arr, $app_id and next if(++$count<=$apk_entity_count);

        &create_task("app_apk","new_apk", @app_arr);
        @app_arr=();
        $count=0;
    }
    $sth->finish();
    
    &create_task("app_apk","new_apk", @app_arr) if (@app_arr>0 && $count>0)
}

sub task_for_updated_app 
{		
    my $sql = "select market_monitor.market_id from market_monitor,market ".
        " where market.id=".$market->{'id'}.
        " and market.id=market_monitor.market_id ".
        " and (market_monitor.status='doing' or TIMESTAMPDIFF( MINUTE,start_time, now() )/60 < market.interval_of_update)";
    my @row_ary= $dbh->selectrow_array($sql);
    return 0 if scalar @row_ary != 0;
    
    warn 'The new circle of app-update for '.$market->{name};

    $sql = "select cycle from market_monitor where market_id=".$market->{'id'}. " order by cycle desc limit 1";
    @row_ary= $dbh->selectrow_array($sql);
    if( (scalar @row_ary) == 0){
        $sql = "insert into market_monitor set status='doing', ".
            "cycle=1, start_time=now(), market_id=".$market->{'id'};
    }else{
        $sql = "insert into market_monitor set status='doing', ".
            "cycle=".($row_ary[0]+1).", start_time=now(), market_id=".$market->{'id'};
    }
    $dbh->do($sql);

    ##group ip for this market
    $sql ="select distinct worker_ip from app_info where market_id=".$market->{'id'};
    my $ip_sth = $dbh->prepare($sql);
    $ip_sth->execute();
    my @app_arr=();
    my $count=0;
    my %app_hash=();

    while(my $ip_hash=$ip_sth->fetchrow_hashref){
        my $ip=$ip_hash->{worker_ip};
        $sql = "select SQL_BUFFER_RESULT app_url_md5,app_url from app_info where ".
            " market_id=$market->{'id'}  and worker_ip='$ip' ".
            " order by last_visited_time, app_url_md5";  
        my $sth = $dbh->prepare($sql);
        $sth->execute();

        while(my $hash=$sth->fetchrow_hashref)
        {
            ++$count;
            $app_hash{$hash->{'app_url_md5'}}=$hash->{'app_url'};
            next if( $count<$app_entity_count);
            &create_task("app_info","update_app", \%app_hash,$ip);
            %app_hash=();
            $count=0;
        }
        $sth->finish();
        &create_task("app_info","update_app", \%app_hash,$ip) if ((scalar keys %app_hash)>0 && $count>0);
    }
}   

sub task_for_new_app
{		
    my %app_hash=();
    my $count=0;

    my $sql = "select SQL_BUFFER_RESULT app_url_md5, app_url from app_source where ".
        " (status='undo' or (status='fail' and TIMESTAMPDIFF( MINUTE,last_visited_time, now() )/60 >2 ) ) ".
        " and market_id=$market->{'id'} ".
        " order by last_visited_time, app_self_id";  
    my $sth = $dbh->prepare($sql);

    $sth->execute();
    while(my $hash=$sth->fetchrow_hashref)
    {
        ++$count;
        $app_hash{$hash->{'app_url_md5'}}=$hash->{'app_url'};
        next if( $count<$app_entity_count);

        &create_task("app_source","new_app", \%app_hash);
        %app_hash=();
        $count=0;
    }
    $sth->finish();
    
    &create_task("app_source","new_app", \%app_hash) if (scalar keys %app_hash>0 && $count>0);
}

##generate a task
sub create_task
{
    my ($table,$task_type,$hash_ref,$ip) = @_;

    my $rc  = $db_helper->start_transaction or die $db_helper->err_str;
    my $sql = "insert into task set task_type='$task_type',status='undo',".
             "market_id=$market->{'id'},request_time=now()";

    $sql.= ",worker_ip='$ip'" if defined($ip);

    my $sth=$dbh->prepare($sql);
    $sth->execute();

    my $task_id=$dbh->last_insert_id(undef,undef,undef,undef);
    $sth=$dbh->prepare("insert into task_detail set task_id=$task_id, detail_id=?,detail_info=?");
    $sth->execute($_,$hash_ref->{$_}) foreach( keys %{$hash_ref});

    if ($table eq 'feeder') {
        $sth=$dbh->prepare("update $table set status='doing' where feeder_id=?")
    }else {
        $sth=$dbh->prepare("update $table set status='doing' where app_url_md5=?");
    }
    $sth->execute($_) foreach(keys %{$hash_ref});

    $logger->info("generate a new task id:$task_id");
    $dbh->commit;
}

sub update_market_monitor 
{		
    my $sql = "select count(*) from task".
        " where task.market_id=".$market->{'id'}.
        " and status!='done'".
        " and task_type!='find_app'".
        " and task_type!='new_app'";
    my @row_ary= $dbh->selectrow_array($sql);
    
    return 0 unless $row_ary[0] == 0;

    $sql = "update market_monitor set status='done', end_time=now() ".
        " where status='doing' ".
        " and market_id=".$market->{'id'};

    $dbh->do($sql);
}
