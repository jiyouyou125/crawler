BEGIN{unshift(@INC, $1) if ($0=~m/(.+)\//);}

use strict;
use DBI;
use Data::Dumper;				
					

#my $temp_folder=&Crawler::Config::get_configValue("TempFolder");
#my $sample_folder=&Crawler::Config::get_configValue("SampleFolder");
my $temp_folder='/var/android/crawler/temp';
my $sample_folder='/var/android/crawler/sample';
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
        &untar_task();
        #restore crawler to idle
# &Crawler::Config::end_work; 
    }
    sleep(60);			# check the scan result every 10 minutes
}
    
    
sub untar_task 
{		
    opendir(DIR, $sample_folder) or die "opendir error";
    my @files= grep { !/^\./ && -f "$sample_folder/$_" } readdir(DIR);
    foreach my $file (@files){
        my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,$atime,$mtime,$ctime,$blksize,$blocks) = stat("$sample_folder/$file");

        if (exists $fileinfo{$file}) {
            my $cmd= "tar -Pxvf $sample_folder/$file -C $temp_folder/$market";
            system($cmd);
            system("rm -f $sample_folder/$file");
#$logger->info("$cmd");
            delete $fileinfo{$file};
        }else{
            $fileinfo{$file}=$size;
        }
    }
    closedir(DIR);
}

