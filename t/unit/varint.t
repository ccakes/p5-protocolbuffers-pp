use strict;
use warnings;
use Test::More;
use lib 'lib';
use ProtocolBuffers::PP::Wire::Varint qw(encode_varint decode_varint);

# Helper to roundtrip
sub roundtrip {
    my ($val) = @_;
    my $encoded = encode_varint($val);
    my $pos = 0;
    my $decoded = decode_varint(\$encoded, \$pos);
    return $decoded;
}

# Basic values
is(roundtrip(0), 0, 'roundtrip 0');
is(roundtrip(1), 1, 'roundtrip 1');
is(roundtrip(127), 127, 'roundtrip 127');
is(roundtrip(128), 128, 'roundtrip 128');
is(roundtrip(300), 300, 'roundtrip 300');

# Known encodings
is(encode_varint(0), "\x00", 'encode 0');
is(encode_varint(1), "\x01", 'encode 1');
is(encode_varint(127), "\x7F", 'encode 127');
is(encode_varint(128), "\x80\x01", 'encode 128');
is(encode_varint(300), "\xAC\x02", 'encode 300');

# max uint32
my $max_u32 = 0xFFFFFFFF;
is(roundtrip($max_u32), $max_u32, 'roundtrip max uint32');

# max uint64
my $max_u64 = 0xFFFFFFFFFFFFFFFF;
is(roundtrip($max_u64), $max_u64, 'roundtrip max uint64');

# Negative values: -1 should encode as 10-byte varint (two's complement)
{
    my $encoded = encode_varint(-1);
    is(length($encoded), 10, '-1 encodes as 10 bytes');
    my $pos = 0;
    my $decoded = decode_varint(\$encoded, \$pos);
    # decoded is uint64 max
    is($decoded, $max_u64, '-1 roundtrips as uint64 max');
}

# Truncated varint
{
    my $buf = "\x80"; # continuation bit set but no more bytes
    my $pos = 0;
    eval { decode_varint(\$buf, \$pos) };
    like($@, qr/Truncated varint/, 'truncated varint detected');
}

# Varint too long
{
    my $buf = "\x80" x 11; # more than 10 bytes of continuation
    my $pos = 0;
    eval { decode_varint(\$buf, \$pos) };
    like($@, qr/Varint too long/, 'overlong varint detected');
}

# Multiple varints in sequence
{
    my $buf = encode_varint(1) . encode_varint(300) . encode_varint(0);
    my $pos = 0;
    is(decode_varint(\$buf, \$pos), 1, 'sequential decode 1st');
    is(decode_varint(\$buf, \$pos), 300, 'sequential decode 2nd');
    is(decode_varint(\$buf, \$pos), 0, 'sequential decode 3rd');
    is($pos, length($buf), 'consumed all bytes');
}

done_testing();
