#download url
BEGIN{unshift(@INC, $1) if ($0=~m/(.+)\//);}

use strict; 
use Google::ProtocolBuffers;

my $proto_filename="market.proto";

Google::ProtocolBuffers->parsefile(
        $proto_filename,
        { generate_code => 'AMMS::Proto.pm', create_accessors => 1 }
    );

