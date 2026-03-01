use strict;
use warnings;
use Test::More;
use lib 'lib';
use ProtocolBuffers::PP::Wire::ZigZag qw(zigzag_encode zigzag_decode);

# Roundtrip helper
sub roundtrip {
    my ($val) = @_;
    return zigzag_decode(zigzag_encode($val));
}

# Known encodings from the protobuf spec
is(zigzag_encode(0),  0, 'zigzag_encode(0) = 0');
is(zigzag_encode(-1), 1, 'zigzag_encode(-1) = 1');
is(zigzag_encode(1),  2, 'zigzag_encode(1) = 2');
is(zigzag_encode(-2), 3, 'zigzag_encode(-2) = 3');
is(zigzag_encode(2147483647), 4294967294, 'zigzag_encode(max_int32)');
is(zigzag_encode(-2147483648), 4294967295, 'zigzag_encode(min_int32)');

# Roundtrips
is(roundtrip(0),  0,  'roundtrip 0');
is(roundtrip(-1), -1, 'roundtrip -1');
is(roundtrip(1),  1,  'roundtrip 1');
is(roundtrip(-2), -2, 'roundtrip -2');
is(roundtrip(2147483647),  2147483647,  'roundtrip max_int32');
is(roundtrip(-2147483648), -2147483648, 'roundtrip min_int32');

# int64 extremes
my $max_i64 = 9223372036854775807;
my $min_i64 = -9223372036854775808;
is(roundtrip($max_i64), $max_i64, 'roundtrip max_int64');
is(roundtrip($min_i64), $min_i64, 'roundtrip min_int64');

done_testing();
