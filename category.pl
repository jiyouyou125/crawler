BEGIN{unshift(@INC, $1) if ($0=~m/(.+)\//);}

use strict;
use DBI;
use Data::Dumper;				
					

#my $temp_folder=&Crawler::Config::get_configValue("TempFolder");
#my $package_folder=&Crawler::Config::get_configValue("SampleFolder");
my $package_folder='/var/android/crawler/package';
my $dest_folder='/home/sli/crawler/';
my $dest_host='/home/sli/crawler/';
#my $logger=Log::Log4perl->get_logger;
				
our %fileinfo;
#our $market="market.android.com";
our $market="www.mumayi.com";
					
#submit the app to analyzer
while(1)
{
    #check this crawler's status from server	
#    if(&Crawler::Config::can_work)	
    {
        &submit_package();
        #restore crawler to idle
# &Crawler::Config::end_work; 
    }
    sleep(60);			# check the scan result every 10 minutes
}
    
    
sub submit_package 
{		
    opendir(DIR, $package_folder) or die "opendir error";
    my @files= grep { !/^\./ && -f "$package_folder/$_" } readdir(DIR);
    foreach my $file (@files){
        my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,$atime,$mtime,$ctime,$blksize,$blocks) = stat("$package_folder/$file");

        if (exists $fileinfo{$file}) {
            my $cmd= "scp -q $package_folder/$file root\@$dest_host:$dest_folder";
            warn "fail to send package $file " if system($cmd) == 0;
            system("rm -f $package_folder/$file");
#$logger->info("$cmd");
            delete $fileinfo{$file};
        }else{
            $fileinfo{$file}=$size;
        }
    }
    closedir(DIR);
}

