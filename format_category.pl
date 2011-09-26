use strict;

my $cat_file = "trustgo_category.txt";

open( CAT, "$cat_file");

my $cat_id=0;
my $sub_cat_id;
my %cat_hash;
my $index=0;

open ( FORMAT, ">cat.format");
while( <CAT> ){
    my $category = $_;
    chomp($category);


    if ($category =~ /^ /){
        $sub_cat_id = $cat_id*100+$index;
        $category =~ s/^\s+//g;
        $category =~ s/\s+$//g;
        $cat_hash{$sub_cat_id} = $category;
        print FORMAT "\t$sub_cat_id   $category\n";
        ++$index;
    }else{
        $index=0;
        ++$cat_id;
        $cat_hash{$cat_id} = $category;
        print FORMAT "$cat_id   $category\n";
    }
}

foreach ( sort  {$a <=> $b} keys %cat_hash ) {
    print $_."\t".$cat_hash{$_}."\n";
}
exit;
