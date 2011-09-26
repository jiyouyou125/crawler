package AMMS::DBHelper;
BEGIN{unshift(@INC, $1) if ($0=~m/(.+)\//);}

use strict; 
use utf8;
use LWP;
use DBI;
use AMMS::Config;
use Digest::MD5 qw(md5_hex);

my $singleton;

sub new
{
    my $class    = shift;

    unless (defined $singleton)
    {

        $singleton = bless {}, $class;

        ##read config file
        $singleton->{ 'CONFIG_HANDLE' } = new AMMS::Config;
        return undef unless $singleton->{ 'CONFIG_HANDLE' };

        ##connect to db
        $singleton->{ 'DB_Handle' } = $singleton->connect_db;
        return undef unless $singleton->{ 'DB_Handle' };
    }

    return $singleton;
}

# connect_db ()
#
#connect to the database of the system
# 
#	Returns value: database handle
#
#
sub connect_db
{
    my $self    = shift;

    my $conn_str;
    my $db_handle;
    my $conf;

    $conf     = $self->{ 'CONFIG_HANDLE' };
    $conn_str ='DBI:mysql';
    $conn_str .= ':'.$conf->getAttribute('MySQLDb');
    $conn_str .= ':'.$conf->getAttribute('MySQLHost');

	$db_handle = DBI->connect(
            $conn_str, 
            $conf->getAttribute('MySQLUser'), 
            $conf->getAttribute('MySQLPasswd'),
            {PrintError=>0,AutoCommit=>1}
            );

    unless (defined $db_handle)
    {
        warn( 'failed to connect database: '.$conf->getAttribute('MySQLDb') );
        return undef;
    }

    $db_handle->{mysql_auto_reconnect}=1;
    warn('failed to set charset "utf8"') unless $db_handle->do('set names "utf8"');
#    warn('failed to set charset "utf8"') unless $db_handle->do('set character_set_results=utf8');
    
    return $db_handle;
}

sub err_str 
{
    my $self      = shift;

    return $self->{ 'DB_Handle' }->errstr;
}



sub start_transaction
{
    my $self      = shift;

    return $self->{ 'DB_Handle' }->begin_work;
}

sub cancel_transaction
{
    my $self      = shift;

    return $self->{ 'DB_Handle' }->rollback;
}

sub end_transaction
{
    my $self      = shift;

    return $self->{ 'DB_Handle' }->commit;
}

sub is_connected
{
    my $self      = shift;

    return $self->{ 'DB_Handle' }->ping;
}

sub get_db_handle
{
    my $self      = shift;

    return $self->{ 'DB_Handle' };
}

sub update_feeder
{
    my $self    = shift;
	my $result  = shift;

    my $sql="update feeder set status=?, last_visited_time=now() where feeder_id=?";
    my $sth=$self->{'DB_Handle'}->prepare($sql);

    foreach my $id ( keys %{ $result } )
    {
        $sth->execute( $result->{$id}->{'status'}, $id) or return 0;
    }

    return 1;
}

sub update_app_source_status
{
    my $self    = shift;
	   my $md5     = shift;
	   my $status  = shift;
	
    $self->{'DB_Handle'}->do("update app_source set status='$status',last_visited_time=now() where app_url_md5='$md5'");

    return 1;
}

sub update_app_info_status
{
    my $self    = shift;
	my $md5     = shift;
	my $status  = shift;

    $status='success' if $status eq 'up_to_date';
    $self->{'DB_Handle'}->do("update app_info set status='$status' where app_url_md5='$md5'");

    return 1;
}


sub restore_task 
{
    my $self        = shift;
    my $market      = shift;
    my $task_type   = shift;

    my $market_info = $self->get_market_info($market);

    my $sql="update task set status='undo' ".
            "where worker_ip='".$self->{'CONFIG_HANDLE'}->getAttribute('host')."' and ". 
            "task_type='$task_type' and ".
            "market_id=".$market_info->{'id'}." and ".
            "status='doing' ";

    $self->{ 'DB_Handle'}->do( $sql ) or return 0;

    return 1;
}

sub update_task_type 
{
    my $self    = shift;
	   my $task_id = shift;
	   my $type    = shift;
	   my $status  = shift;

    $self->{ 'DB_Handle'}->do("update task set task_type='$type', status='undo',task_changed_time=now() where task_id=$task_id") or return 0;

    return 1;
}



sub update_task 
{
    my $self        = shift;
	my $task_id     = shift;
	my $status      = shift;

    $self->{ 'DB_Handle'}->do("update task set status='$status', done_time=now() where task_id=$task_id") or return 0;

    return 1;
}

sub get_task 
{
    my $self      = shift;
	   my $market    = shift;
	   my $task_type = shift;

 	  my $sql;
    my $sth;
    my $task_id;
    my $market_info = $self->get_market_info($market);

    $sql = "select task_id from task where market_id=$market_info->{'id'} and task_type='$task_type' and status='undo' ";
    $sql .= " and worker_ip='".$self->{ 'CONFIG_HANDLE' }->getAttribute('host')."'" if ($task_type ne 'new_app' and $task_type ne 'find_app');
    $sql .= " order by request_time asc limit 1";
    $sth =$self->{ 'DB_Handle'}->prepare($sql);
    $sth->execute();

    return 0 if $sth->rows == 0;
    
    $task_id = ($sth->fetchrow_array)[0];

    $sql="update task set worker_ip='".$self->{ 'CONFIG_HANDLE' }->getAttribute('host')."', start_time=now(),status='doing' where task_id=$task_id";
    $self->{ 'DB_Handle'}->do($sql);

    return $task_id;
}

sub get_app_info_from_db
{
    my $self    = shift;
    my $md5     = shift;

    my $fields  = join(',',@_);
    my $sql=qq{select $fields from app_info where app_url_md5='$md5'};
    my $sth=$self->{ 'DB_Handle'}->prepare($sql);
     
    $sth->execute();

    my $info_hash=$sth->fetchrow_hashref;

    return $info_hash;
}

sub get_apk_info
{
    my $self    = shift;
    my $task_id = shift;

    my $app_url_md5;
    my $apk_url;
    my %detail;

 	my $sql=qq{select app_url_md5,apk_url from app_apk where app_url_md5 in (select detail_id from task_detail where task_id=$task_id) };
    my $sth=$self->{ 'DB_Handle'}->prepare($sql);
    $sth->execute();
    $sth->bind_columns(\$app_url_md5,\$apk_url);
    
    $detail{$app_url_md5} = $apk_url  while( $sth->fetch );

    return %detail;
}


sub get_last_modified_time 
{
    my $self    = shift;
    my $md5     = shift;

 	my $sql=qq{select last_modified_time from app_info where app_url_md5='$md5'};
    my $sth=$self->{ 'DB_Handle'}->prepare($sql);
    $sth->execute();
    
    my $modified_time=$sth->fetchrow_array;

    return $modified_time;
}

sub get_feed_url
{
    my $self    = shift;
    my $task_id = shift;

	   my $sql;
    my $sth;
    my %detail;
    my $feeder_id;
    my $feeder_url;

 	  $sql=qq{select feeder_id,feeder_url from feeder where feeder_id in (select detail_id from task_detail where task_id=$task_id) };
    $sth=$self->{ 'DB_Handle'}->prepare($sql);
    $sth->execute();
    $sth->bind_columns(\$feeder_id,\$feeder_url);
    
    $detail{$feeder_id} = $feeder_url while( $sth->fetch );

    return %detail;
}

sub get_app_info_url
{
    my $self    = shift;
    my $task_id = shift;

    my $app_url_md5;
    my $app_url;
    my %detail;

 	my $sql=qq{select app_url_md5,app_url from app_info where app_url_md5 in (select detail_id from task_detail where task_id=$task_id) };
    my $sth=$self->{ 'DB_Handle'}->prepare($sql);
    $sth->execute();
    $sth->bind_columns(\$app_url_md5,\$app_url);
    
    $detail{$app_url_md5} = $app_url  while( $sth->fetch );

    return %detail;
}

sub get_task_detail{
    my $self    = shift;
    my $task_id = shift;

    my $detail_id;
    my $detail_info;
    my %detail;

 	  my $sql=qq{select detail_id, detail_info from task_detail where task_id=$task_id };
    my $sth=$self->{ 'DB_Handle'}->prepare($sql);
    $sth->execute();
    $sth->bind_columns(\$detail_id,\$detail_info);
    
    $detail{$detail_id} = $detail_info while( $sth->fetch );

    return %detail;

}

sub get_app_source_url
{
    my $self    = shift;
    my $task_id = shift;

    my $app_url_md5;
    my $app_url;
    my %detail;

 	my $sql=qq{select app_url_md5,app_url from app_source where app_url_md5 in (select detail_id from task_detail where task_id=$task_id) };
    my $sth=$self->{ 'DB_Handle'}->prepare($sql);
    $sth->execute();
    $sth->bind_columns(\$app_url_md5,\$app_url);
    
    $detail{$app_url_md5} = $app_url  while( $sth->fetch );

    return %detail;
}

sub save_url_from_feeder
{
    my $self        = shift;
    my $feeder_id   = shift;
    my $url         = shift;
    my $status      = shift;

    my $sql="replace into feed_info set feed_url_md5='".md5_hex($url)."',feeder_id=$feeder_id, status='$status',last_visited_time=now(),feed_url=".$self->{'DB_Handle'}->quote($url);
    return 0 unless $self->{'DB_Handle'}->do($sql);

	return 1;
}

sub get_market_info
{
    my $self    = shift;
    my $market  = shift;

    my $market_info;

    my $sql="select * from market "; 
    $sql .= "where name='$market'" if defined($market);
    
    my $sth=$self->{'DB_Handle'}->prepare($sql);
    $sth->execute();
    
    
    $market_info =$sth->fetchrow_hashref;
#{
#        my %info;
#        $info{'market_id'}= $hash->{'id'};
#        $info{'feeder_entity_of_task'}= $hash->{'feeder_entity_of_task'};
#        $market_info{ $hash->{'name'}  } = \%info;
#    }

    return $market_info;
}

sub get_markets
{
    my $self    = shift;

    my @markets;

    my $sql="select name from market "; 
    my $sth=$self->{'DB_Handle'}->prepare($sql);
    $sth->execute();
    
    
    while( my $hash=$sth->fetchrow_hashref)
    {
        push @markets,$hash->{'name'};
    }

    return @markets;
}



sub save_app_into_source
{
    my $self        = shift;
    my $feeder_id   = shift;
    my $market      = shift;
    my $apps        = shift;

    my $sql="select id from market where name='$market'";
    my $hash_ref=$self->{'DB_Handle'}->selectrow_hashref($sql);
    my $market_id=$hash_ref->{'id'};

    die "Please first fill in market info\n\n" unless defined $market_id;

    foreach my $app_self_id ( keys %{ $apps } ) 
    {
        my $md5=md5_hex($apps->{$app_self_id});
        $sql='insert into app_source set '.
            " app_url_md5='$md5'".
            ',app_self_id="'.$app_self_id.'"'.
            ',market_id='.$market_id.
            ',feeder_id='.$feeder_id.
            ',app_url='.$self->{'DB_Handle'}->quote($apps->{$app_self_id}).
            ',status="undo"';
	    
        if($self->{ 'DB_Handle' }->do($sql)<=0)
        {
#my $err_str=sprintf("fail to insert app $apps->{$app_self_id}");
#$self->{ 'CONFIG_HANDLE' }->getAttribute('LOGGER')->error($err_str);
            next;
        }
    }

    return 1;
}

sub insert_app_info
{
    my $self        = shift;
    my $app_info    = shift;

    my $app_url_md5 = $app_info->{'app_url_md5'};
   
    ##invaild app url,don't insert into app_info
    return  1 if $app_info->{'status'} eq 'invalid'; 

    my $sql = "replace into app_info set ";
    $sql .= " app_url_md5='$app_url_md5'";
    $sql .= ",support_os='android'";
    $sql .= ",app_capacity='tablet,phone'";
    $sql .= ",status='".$app_info->{'status'}."'";
    $sql .= ",visited_times=1";
    $sql .= ",updated_times=1";
    $sql .= ",market_id=$app_info->{market_id}";
    $sql .= ",last_visited_time=now()";
    $sql .= ",first_visited_time=now()";
    $sql .= ",last_modified_time=now()";
    $sql .= ",worker_ip='".$self->{ 'CONFIG_HANDLE' }->getAttribute('host')."'";
    $sql .= ",last_success_visited_time=now()";
    $sql .= $self->concatenate_string_field( 'app_name', $app_info );
    $sql .= $self->concatenate_string_field( 'currency', $app_info );
    $sql .= $self->concatenate_string_field( 'price', $app_info );
    $sql .= $self->concatenate_string_field( 'note', $app_info );
    $sql .= $self->concatenate_string_field( 'system_requirement', $app_info );
    $sql .= $self->concatenate_string_field( 'last_update', $app_info );
    $sql .= $self->concatenate_string_field( 'current_version', $app_info );
    $sql .= $self->concatenate_string_field( 'official_category', $app_info );
    $sql .= $self->concatenate_string_field( 'min_os_version', $app_info );
    $sql .= $self->concatenate_string_field( 'max_os_version', $app_info );
    $sql .= $self->concatenate_string_field( 'age_rating',$app_info );
    $sql .= $self->concatenate_string_field( 'app_url',$app_info );
    $sql .= $self->concatenate_string_field( 'website',$app_info );
    $sql .= $self->concatenate_string_field( 'resolution',$app_info );
    $sql .= $self->concatenate_string_field( 'support_website',$app_info );
    $sql .= $self->concatenate_string_field( 'author', $app_info );
    $sql .= $self->concatenate_string_field( 'app_qr', $app_info );
    $sql .= $self->concatenate_string_field( 'trustgo_category_id',$app_info );
    $sql .= $self->concatenate_numeric_field( 'size', $app_info );
    $sql .= $self->concatenate_numeric_field( 'official_rating_stars',$app_info );
    $sql .= $self->concatenate_numeric_field( 'official_rating_times',$app_info );
    $sql .= $self->concatenate_numeric_field( 'total_install_times',$app_info );

    if($self->{ 'DB_Handle' }->do($sql)<=0)
    {
        $self->{ 'CONFIG_HANDLE' }->getAttribute('LOGGER')->error(
                sprintf("fail to save app, App URL MD5:%s, Error:%s",
                        $app_url_md5,$self->{'DB_Handle'}->errstr
                    )
            );
        $app_info->{ 'status' } ='fail';
        return 0;
    }
          
 
    return 1;
}

sub insert_apk_info
{
    my $self        = shift;
    my $apk_info    = shift;
    my $app_url_md5 = $apk_info->{'app_url_md5'}; 
   
    ##invaild app url,don't insert into app_info
    return  1 if $apk_info->{'status'} eq 'invalid'; 

    #insert new apps into apk table
    my $sql = "replace into app_apk set ";
    $sql .= " app_url_md5='$app_url_md5'";
    $sql .= ",status='".$apk_info->{'status'}."'";
    $sql .= ",insert_time=now()";
    $sql .= ",apk_url=".$self->{ 'DB_Handle' }->quote($apk_info->{'apk_url'});
    if ($apk_info->{'status'} eq 'success') 
    {
    $sql .= ",need_submmit='yes'";
    $sql .= $self->concatenate_string_field('app_unique_name',$apk_info);
    } 
    else
    {
    $sql .= ",need_submmit='no'";
    }


    if($self->{ 'DB_Handle' }->do($sql)<=0)
    {
        $self->{ 'CONFIG_HANDLE' }->getAttribute('LOGGER')->error(
                "fail to insert apk for $app_url_md5, Error:".$self->{'DB_Handle'}->errstr
                );
        $apk_info->{ 'status' } ='fail';
	use Data::Dumper;
open( ERR, '>>/root/apk.log');
print ERR "$sql\n";
print ERR "$app_url_md5\n";
print ERR "status:".$apk_info->{'status'}.'\n';
print ERR "url:".$apk_info->{'apk_url'}.'\n';
close( ERR);
        return 0;
    }

    return 1;
}

sub mark_as_new_apk
{
    my $self    = shift;
    my $app     = shift;
    my $status      = $app->{'status'};
    my $app_info    = $app->{'app_info'};
    my $app_url_md5 = md5_hex($app_info->{'app_url'});
  
#insert new apps into apk table
    my $sql = "update app_apk set ";
    $sql .= ",status='undo'";
    $sql .= ",need_submmit='no'";
    $sql .= " where app_url_md5='$app_url_md5'";

    if($self->{ 'DB_Handle' }->do($sql)<=0)
    {
        $self->{ 'CONFIG_HANDLE' }->getAttribute('LOGGER')->error(
                "fail to update apk App url d5:$app_url_md5, Error:".$self->{'DB_Handle'}->errstr);
        $app_info->{ 'status' } ='fail';
        return 0;
    }

    return 1;
}

sub update_app_info
{
    my $self        = shift;
    my $app_info    = shift;

    my $status      = $app_info->{'status'};
    my $app_url_md5 = $app_info->{'app_url_md5'};
   

    my $sql="select updated_times,visited_times,last_modified_time from app_info where app_url_md5='$app_url_md5'";
    my $sth=$self->{'DB_Handle'}->prepare($sql);
    $sth->execute;

    my ($updated_times,$visited_times,$last_modified_time)=$sth->fetchrow();
    $visited_times++;

    $sql = "update app_info set ";
    $sql .= " visited_times=$visited_times";
    $sql .= ",last_visited_time=now()";
    $sql .= ",status='$status'";

    if( $status eq 'success' )#means this apps has some change
    {
        $updated_times++;
        $sql .= ",updated_times=$updated_times";
        $sql .= ",last_modified_time=now()";
        $sql .= ",last_success_visited_time=now()";
        $sql .= ",app_url_md5='$app_url_md5'";
        $sql .= ",support_os='android'";
        $sql .= ",app_capacity='tablet,phone'";
        $sql .= $self->concatenate_string_field( 'app_name', $app_info );
        $sql .= $self->concatenate_string_field( 'currency', $app_info );
        $sql .= $self->concatenate_string_field( 'price', $app_info );
        $sql .= $self->concatenate_string_field( 'note', $app_info );
        $sql .= $self->concatenate_string_field( 'system_requirement', $app_info );
        $sql .= $self->concatenate_string_field( 'last_update', $app_info );
        $sql .= $self->concatenate_string_field( 'current_version', $app_info );
        $sql .= $self->concatenate_string_field( 'official_category', $app_info );
        $sql .= $self->concatenate_string_field( 'min_os_version', $app_info );
        $sql .= $self->concatenate_string_field( 'max_os_version', $app_info );
        $sql .= $self->concatenate_string_field( 'age_rating',$app_info );
        $sql .= $self->concatenate_string_field( 'app_url',$app_info );
        $sql .= $self->concatenate_string_field( 'website',$app_info );
        $sql .= $self->concatenate_string_field( 'resolution',$app_info );
        $sql .= $self->concatenate_string_field( 'support_website',$app_info );
        $sql .= $self->concatenate_string_field( 'author', $app_info );
        $sql .= $self->concatenate_string_field( 'app_qr', $app_info );
        $sql .= $self->concatenate_string_field( 'trustgo_category_id',$app_info );
        $sql .= $self->concatenate_numeric_field( 'size', $app_info );
        $sql .= $self->concatenate_numeric_field( 'official_rating_stars',$app_info );
        $sql .= $self->concatenate_numeric_field( 'official_rating_times',$app_info );
        $sql .= $self->concatenate_numeric_field( 'total_install_times',$app_info );
    }

    $sql .= " where app_url_md5='$app_url_md5'";

    if($self->{ 'DB_Handle' }->do($sql)<=0)
    {
        $self->{ 'CONFIG_HANDLE' }->getAttribute('LOGGER')->error(
                sprintf("fail to save app, AppID:%d, Error:%s",
                        $app_url_md5,$self->{'DB_Handle'}->errstr
                    )
            );
        $app_info->{ 'status' } ='fail';
        return 0;
    }
          

    return 1;
}

sub concatenate_numeric_field
{
    my $self        = shift;
    my $field       = shift;
    my $info        = shift;

    return ", $field=$info->{$field}" if defined $info->{$field};

    return ;
}

sub concatenate_string_field
{
    my $self        = shift;
    my $field       = shift;
    my $info        = shift;

    if (defined $info->{$field}){
        my $str =  $self->{ 'DB_Handle' }->quote($info->{$field});
        utf8::decode($str);
        return ", $field=$str";
    }

    return;
}



sub update_apk_info
{
    my $self        = shift;
    my $apk_info    = shift;
    my $status      = $apk_info->{'status'};
    my $app_url_md5 = $apk_info->{'app_url_md5'}; 

    return 1 if $status ne 'success';

    my $sql = "update app_apk set ";
    $sql .= " last_visited_time=now()";
    $sql .= ",status='$status'";
    $sql .= $self->concatenate_string_field('apk_url',$apk_info);
    if ($status eq 'success') 
    {
    $sql .= ",need_submmit='yes'";
    $sql .= $self->concatenate_string_field('app_unique_name',$apk_info);
    } 
    else
    {
    $sql .= ",need_submmit='no'";
    }

    $sql .= " where app_url_md5='$app_url_md5' ";

    if($self->{ 'DB_Handle' }->do($sql)<=0)
    {
        $self->{ 'CONFIG_HANDLE' }->getAttribute('LOGGER')->error(
                "fail to save apk,  Error:".$self->{'DB_Handle'}->errstr
                );
        return 0;
    }

    return 1;
}

sub google_account_info
{
    my $self      = shift;
	my $market    = shift;
	my $task_type = shift;

 	my $sql;
    my $sth;
    my $task_id;
    my $market_info = $self->get_market_info($market);

    $sql = qq{select task_id from task where market_id=$market_info->{'id'} and task_type='$task_type' and status='undo' order by request_time asc limit 1};
    $sth =$self->{ 'DB_Handle'}->prepare($sql);
    $sth->execute();

    return 0 if $sth->rows == 0;
    
    $task_id = ($sth->fetchrow_array)[0];

    $sql="update task set worker_ip='".$self->{ 'CONFIG_HANDLE' }->getAttribute('host')."', start_time=now(),status='doing' where task_id=$task_id";
    $self->{ 'DB_Handle'}->do($sql);

    return $task_id;
}


sub get_category_from_feeder
{
    my $self    = shift;
    my $app_url_md5 = shift;

    my %cat_hash;

    my $sql="select parent_category,sub_category from feeder,app_source where app_url_md5='$app_url_md5' and app_source.feeder_id=feeder.feeder_id"; 
    
    my $sth=$self->{'DB_Handle'}->prepare($sql);
    $sth->execute();
    
    
    my $hash=$sth->fetchrow_hashref;
    $cat_hash{'parent_category'}= $hash->{'parent_category'};
    $cat_hash{'sub_category'}= $hash->{'sub_category'};

    return %cat_hash;
}

sub save_package 
{
    my $self    = shift;
    my $task_id = shift;
    my $package_name = shift;
   
    my $sql = "insert into package set ";
    $sql .= " task_id=$task_id";
    $sql .= ",package_name='$package_name'";
    $sql .= ",status='undo'";
    $sql .= ",worker_ip='".$self->{ 'CONFIG_HANDLE' }->getAttribute('host')."'";
    $sql .= ",insert_time=now()";


    if($self->{ 'DB_Handle' }->do($sql)<=0)
    {
        $self->{ 'CONFIG_HANDLE' }->getAttribute('LOGGER')->error(
                "fail to insert package for task $task_id, Error:".$self->{'DB_Handle'}->errstr
                );
        return 0;
    }

    return 1;
}

sub save_extra_info{
    my $self = shift;
    my $app_url_md5 = shift;
    my $arg = shift;

    my $sql = "replace into app_extra_info(app_url_md5,data_key,data_value) values(?,?,?)";
    my $sth = $self->{ 'DB_Handle' }->prepare($sql);
    eval{
        if(ref $arg eq "HASH"){
            foreach my $key(keys %$arg){
                $sth->execute($app_url_md5,$key,$arg->{$key});
            }
        }
    };
    if($@){
        $self-> { 'CONFIG_HANDLE' }->getAttribute('LOGGER')->error(
            "fail to insert extra_info for app_url_md5:$app_url_md5,Error:".$self->{'DB_Handle'}->errstr;
        );
        return 0;
    }
    return 1;
}

sub get_extra_info{
    my $self = shift;
    my $app_url_md5 = shift;
    my $key = shift;
    my $sql;
    my $sql_con = "";
    if($key){
        $sql = " and data_key = ?";
    }
    my $sql = "select data_value,data_key from app_extra_info where app_url_md5 = ? ".$sql_con." limit 1";
    if($key){
        my $row = $self-> { 'DB_Handle' }->selectrow_hashref($sql,undef,$app_url_md5,$key); 
        if($row){
            return $row->{data_value};
        }
    }
    my $sth = $self-> {'DB_Handle'}->prepare($sql);
    my @rows;
    while(my $row = $sth->fetchrow_hashref){
        push @rows, $row; 
    }
    return @rows;
}


1;

__END__
