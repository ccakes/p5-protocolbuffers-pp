use strict;
use warnings;
use Test::More;
use lib 'lib';
use ProtocolBuffers::PP::Wire::Bytes qw(
    encode_fixed32 decode_fixed32
    encode_fixed64 decode_fixed64
    encode_sfixed32 decode_sfixed32
    encode_sfixed64 decode_sfixed64
    encode_float decode_float
    encode_double decode_double
);

# Helper
sub rt32 {
    my $enc = encode_fixed32($_[0]);
    my $pos = 0;
    return decode_fixed32(\$enc, \$pos);
}
sub rt64 {
    my $enc = encode_fixed64($_[0]);
    my $pos = 0;
    return decode_fixed64(\$enc, \$pos);
}
sub rts32 {
    my $enc = encode_sfixed32($_[0]);
    my $pos = 0;
    return decode_sfixed32(\$enc, \$pos);
}
sub rts64 {
    my $enc = encode_sfixed64($_[0]);
    my $pos = 0;
    return decode_sfixed64(\$enc, \$pos);
}
sub rtf {
    my $enc = encode_float($_[0]);
    my $pos = 0;
    return decode_float(\$enc, \$pos);
}
sub rtd {
    my $enc = encode_double($_[0]);
    my $pos = 0;
    return decode_double(\$enc, \$pos);
}

# fixed32
is(rt32(0), 0, 'fixed32 0');
is(rt32(1), 1, 'fixed32 1');
is(rt32(0xFFFFFFFF), 0xFFFFFFFF, 'fixed32 max');
is(length(encode_fixed32(0)), 4, 'fixed32 is 4 bytes');

# fixed64
is(rt64(0), 0, 'fixed64 0');
is(rt64(0xFFFFFFFFFFFFFFFF), 0xFFFFFFFFFFFFFFFF, 'fixed64 max');
is(length(encode_fixed64(0)), 8, 'fixed64 is 8 bytes');

# sfixed32
is(rts32(0), 0, 'sfixed32 0');
is(rts32(1), 1, 'sfixed32 1');
is(rts32(-1), -1, 'sfixed32 -1');
is(rts32(2147483647), 2147483647, 'sfixed32 max');
is(rts32(-2147483648), -2147483648, 'sfixed32 min');

# sfixed64
is(rts64(0), 0, 'sfixed64 0');
is(rts64(-1), -1, 'sfixed64 -1');
is(rts64(9223372036854775807), 9223372036854775807, 'sfixed64 max');
is(rts64(-9223372036854775808), -9223372036854775808, 'sfixed64 min');

# float
ok(abs(rtf(0.0)) < 1e-10, 'float 0.0');
ok(abs(rtf(1.5) - 1.5) < 1e-6, 'float 1.5');
ok(abs(rtf(-1.5) - (-1.5)) < 1e-6, 'float -1.5');

# float NaN
{
    my $nan = rtf(unpack("f<", pack("V", 0x7FC00000)));
    ok($nan != $nan, 'float NaN roundtrips');  # NaN != NaN
}

# float Inf
{
    my $inf = 9**9**9;
    is(rtf($inf), $inf, 'float +Inf');
    is(rtf(-$inf), -$inf, 'float -Inf');
}

# float -0.0
{
    my $neg_zero = -0.0;
    my $enc = encode_float($neg_zero);
    my $pos = 0;
    my $dec = decode_float(\$enc, \$pos);
    ok($dec == 0, 'float -0.0 is zero');
    is(sprintf("%g", $dec), '-0', 'float -0.0 preserves sign');
}

# double
ok(abs(rtd(0.0)) < 1e-15, 'double 0.0');
ok(abs(rtd(3.14159265358979) - 3.14159265358979) < 1e-14, 'double pi');

# double NaN
{
    my $nan = rtd(unpack("d<", pack("Q<", 0x7FF8000000000000)));
    ok($nan != $nan, 'double NaN roundtrips');
}

# double Inf
{
    my $inf = 9**9**9;
    is(rtd($inf), $inf, 'double +Inf');
    is(rtd(-$inf), -$inf, 'double -Inf');
}

# double -0.0
{
    my $neg_zero = -0.0;
    my $enc = encode_double($neg_zero);
    my $pos = 0;
    my $dec = decode_double(\$enc, \$pos);
    is(sprintf("%g", $dec), '-0', 'double -0.0 preserves sign');
}

# Truncation errors
{
    my $buf = "\x00\x00"; # only 2 bytes, need 4
    my $pos = 0;
    eval { decode_fixed32(\$buf, \$pos) };
    like($@, qr/Truncated/, 'fixed32 truncation detected');
}

done_testing();
