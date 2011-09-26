#!/usr/bin/perl 
use utf8;  
use Encode;  
use URI::Escape;  
  
$\ = "\n";  
  
#从unicode得到utf8编码  
$str = '%u6536';  
$str =~ s/\%u([0-9a-fA-F]{4})/pack("U",hex($1))/eg;  
$str = encode( "utf8", $str );  
print uc unpack( "H*", $str );  
  
 # 从unicode得到gb2312编码  
  $str = '%u6536';  
  $str =~ s/\%u([0-9a-fA-F]{4})/pack("U",hex($1))/eg;  
  $str = encode( "gb2312", $str );  
  print uc unpack( "H*", $str );  
    
# 从中文得到utf8编码  
#    $str = "收";  
#    print uri_escape($str);  
      
#      # 从utf8编码得到中文  
#      $utf8_str = uri_escape("收");  
#      print uri_unescape($str);  
#        
#        # 从中文得到perl unicode  
#        utf8::decode($str);  
#        @chars = split //, $str;  
#        foreach (@chars) {  
#            printf "%x ", ord($_);  
#            }  
#              
#              # 从中文得到标准unicode  
#              $a = "汉语";  
#              $a = decode( "utf8", $a );  
#              map { print "\\u", sprintf( "%x", $_ ) } unpack( "U*", $a );  
#                
#                # 从标准unicode得到中文  
#                $str = '%u6536';  
#                $str =~ s/\%u([0-9a-fA-F]{4})/pack("U",hex($1))/eg;  
#                $str = encode( "utf8", $str );  
#                print $str;  
#                  
#                  # 从perl unicode得到中文  
#                  my $unicode = "\x{505c}\x{8f66}";  
#                  print encode( "utf8", $unicode );
