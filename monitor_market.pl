#!/usr/bin/perl
BEGIN{unshift(@INC, $1) if ($0=~m/(.+)\//);}
use strict;
use warnings;

use AMMS::Util;

die "\nplease check config parameter\n" unless init_gloabl_variable;
die "\nNot enough disk space or Network is bad\n" if not &check_host_status;

my @markets_be_monitored = @ARGV;

my $conf_file = $conf->getAttribute('BaseBinDir').'/default.cfg';
my $daemon_script   = $conf->getAttribute('BaseBinDir').'/daemon.pl'; 
my %program_table = (
        'google'=>{'host'=>'market.android.com','script'=>'google.pl','task_type'=>[qw(new_app update_app )]},
        'google_multi_lang'=>{'host'=>'market.android.com','script'=>'google_multi_lang.pl','task_type'=>[qw(multi-lang)]},
        'mumayi'=>{'host'=>'www.mumayi.com','script'=>'mumayi.pl','task_type'=>[qw(find_app new_app update_app )]},
        'amazon'=>{'host'=>'www.amazon.com','script'=>'amazon.pl','task_type'=>[qw(find_app new_app update_app )]},
        'aimi8'=>{'host'=>'www.aimi8.com','script'=>'aimi8.pl','task_type'=>[qw(find_app  new_app update_app )]},
        'hiapk'=>{'host'=>'www.hiapk.com','script'=>'hiapk.pl','task_type'=>[qw(find_app new_app  update_app)]},
        '163'=>{'host'=>'m.163.com','script'=>'163.pl','task_type'=>[qw(find_app new_app update_app)]},
        'gfan'=>{'host'=>'www.gfan.com','script'=>'gfan.pl','task_type'=>[qw(find_app new_app update_app )]},
        'appchina'=>{'host'=>'www.appchina.com','script'=>'appchina.pl','task_type'=>[qw(find_app new_app update_app )]},
        'eoemarket'=>{'host'=>'www.eoemarket.com','script'=>'eoemarket.pl','task_type'=>[qw(find_app new_app update_app)]},
        'goapk'=>{'host'=>'www.goapk.com','script'=>'goapk.pl','task_type'=>[qw(find_app new_app update_app )]},
        'dangle'=>{'host'=>'android.d.cn','script'=>'dangle.pl','task_type'=>[qw(find_app new_app  update_app )]},
        'nduoa'=>{'host'=>'www.nduoa.com','script'=>'nduoa.pl','task_type'=>[qw(find_app new_app  update_app )]},
		'tgbus' =>{'host'=>'dg.tgbus.com','script'=>'tgbus.pl','task_type'=>[qw(new_app)]},
        'anfone'=>{'host'=>'www.anfone.com','script'=>'anfone.pl','task_type'=>[qw(find_app new_app  update_app )]},
        'zol' => {'host' => 'sj.zol.com.cn', 'script' => 'zol.pl','task_type' => [qw(find_app new_app)]},
        "1mobile"=> {'host' => 'm.1mobile.com','script' => '1mobile.pl','task_type'=>[qw(find_app new_app)]},
        "brothersoft" => {'host'=>'www.brothersoft.com', 'script' => 'brothersoft.pl', 'task_type' => [qw(find_app new_app)]},
        "mobango" => { 'host' => 'www.mobango.com', 'script' => 'mobango.pl', 'task_type'=>[qw(find_app new_app)]},
        );

foreach( @markets_be_monitored )
{
    create_worker($program_table{$_}) if $program_table{$_};
}

#create_worker('mumayi.pl','new_app');


sub create_worker
{
    use Proc::Daemon;

    my $market_info = shift;


    foreach my $task_type ( @{ $market_info->{'task_type'} } )
    {

        my $exec_command= "perl  $daemon_script ".
                            " -t $task_type".
                            " -c $conf_file".
                            " -m ".$market_info->{'host'}.
                            " -p ".$market_info->{'script'};
#if(fork() == 0)
        if(1)
        {
            system("$exec_command &");
        } else {
        }
        sleep(1);
    }
}
