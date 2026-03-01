use strict;
use warnings;
use Test::More;
use lib 'lib';
use ProtocolBuffers::PP::Wire::Tags qw(encode_tag decode_tag);
use ProtocolBuffers::PP::Wire;

# field 1, wire type 0 (varint) = 0x08
is(encode_tag(1, ProtocolBuffers::PP::Wire::VARINT), "\x08", 'field 1, varint = 0x08');

# field 2, wire type 2 (length delimited) = 0x12
is(encode_tag(2, ProtocolBuffers::PP::Wire::LENGTH_DELIMITED), "\x12", 'field 2, len = 0x12');

# field 1, wire type 2 = 0x0A
is(encode_tag(1, ProtocolBuffers::PP::Wire::LENGTH_DELIMITED), "\x0A", 'field 1, len = 0x0A');

# field 15, wire type 0 = 0x78
is(encode_tag(15, ProtocolBuffers::PP::Wire::VARINT), "\x78", 'field 15, varint');

# field 16, wire type 0 = two byte tag
{
    my $tag = encode_tag(16, ProtocolBuffers::PP::Wire::VARINT);
    is(length($tag), 2, 'field 16 needs 2 bytes');
    my $pos = 0;
    my ($fn, $wt) = decode_tag(\$tag, \$pos);
    is($fn, 16, 'decode field 16');
    is($wt, ProtocolBuffers::PP::Wire::VARINT, 'decode wire type varint');
}

# Large field number
{
    my $tag = encode_tag(536870911, ProtocolBuffers::PP::Wire::VARINT);  # max field number (2^29 - 1)
    my $pos = 0;
    my ($fn, $wt) = decode_tag(\$tag, \$pos);
    is($fn, 536870911, 'large field number roundtrip');
    is($wt, ProtocolBuffers::PP::Wire::VARINT, 'large field wire type');
}

# Roundtrip various wire types
for my $wt (0..5) {
    for my $fn (1, 2, 15, 16, 100, 10000) {
        my $tag = encode_tag($fn, $wt);
        my $pos = 0;
        my ($dfn, $dwt) = decode_tag(\$tag, \$pos);
        is($dfn, $fn, "roundtrip field $fn, wt $wt: field number");
        is($dwt, $wt, "roundtrip field $fn, wt $wt: wire type");
    }
}

done_testing();
