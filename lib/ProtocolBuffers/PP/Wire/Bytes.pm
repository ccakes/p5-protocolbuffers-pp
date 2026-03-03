package ProtocolBuffers::PP::Wire::Bytes;
use strict;
use warnings;
use ProtocolBuffers::PP::Wire::Varint qw(encode_varint decode_varint);
use ProtocolBuffers::PP::Error;

use Exporter 'import';
our @EXPORT_OK = qw(
    encode_fixed32 decode_fixed32
    encode_fixed64 decode_fixed64
    encode_sfixed32 decode_sfixed32
    encode_sfixed64 decode_sfixed64
    encode_float decode_float
    encode_double decode_double
    encode_length_delimited decode_length_delimited
);

sub encode_fixed32  { return pack("V", (defined $_[0] && $_[0] ne '') ? $_[0] : 0) }
sub decode_fixed32  {
    my ($buf_ref, $pos_ref) = @_;
    _check_len($buf_ref, $pos_ref, 4);
    my $val = unpack("V", substr($$buf_ref, $$pos_ref, 4));
    $$pos_ref += 4;
    return $val;
}

sub encode_fixed64  { return pack("Q<", (defined $_[0] && $_[0] ne '') ? $_[0] : 0) }
sub decode_fixed64  {
    my ($buf_ref, $pos_ref) = @_;
    _check_len($buf_ref, $pos_ref, 8);
    my $val = unpack("Q<", substr($$buf_ref, $$pos_ref, 8));
    $$pos_ref += 8;
    return $val;
}

sub encode_sfixed32 { return pack("l<", (defined $_[0] && $_[0] ne '') ? $_[0] : 0) }
sub decode_sfixed32 {
    my ($buf_ref, $pos_ref) = @_;
    _check_len($buf_ref, $pos_ref, 4);
    my $val = unpack("l<", substr($$buf_ref, $$pos_ref, 4));
    $$pos_ref += 4;
    return $val;
}

sub encode_sfixed64 { return pack("q<", (defined $_[0] && $_[0] ne '') ? $_[0] : 0) }
sub decode_sfixed64 {
    my ($buf_ref, $pos_ref) = @_;
    _check_len($buf_ref, $pos_ref, 8);
    my $val = unpack("q<", substr($$buf_ref, $$pos_ref, 8));
    $$pos_ref += 8;
    return $val;
}

sub encode_float    { return pack("f<", (defined $_[0] && $_[0] ne '') ? $_[0] : 0) }
sub decode_float    {
    my ($buf_ref, $pos_ref) = @_;
    _check_len($buf_ref, $pos_ref, 4);
    my $val = unpack("f<", substr($$buf_ref, $$pos_ref, 4));
    $$pos_ref += 4;
    return $val;
}

sub encode_double   { return pack("d<", (defined $_[0] && $_[0] ne '') ? $_[0] : 0) }
sub decode_double   {
    my ($buf_ref, $pos_ref) = @_;
    _check_len($buf_ref, $pos_ref, 8);
    my $val = unpack("d<", substr($$buf_ref, $$pos_ref, 8));
    $$pos_ref += 8;
    return $val;
}

sub encode_length_delimited {
    my ($data) = @_;
    $data = '' unless defined $data;
    # Ensure byte mode — string values with Perl's internal UTF-8 flag
    # must be encoded as UTF-8 bytes for correct length and concatenation
    utf8::encode($data) if utf8::is_utf8($data);
    return encode_varint(length($data)) . $data;
}

sub decode_length_delimited {
    my ($buf_ref, $pos_ref) = @_;
    my $len = decode_varint($buf_ref, $pos_ref);
    if ($$pos_ref + $len > length($$buf_ref)) {
        ProtocolBuffers::PP::Error->throw('decode', 'Truncated length-delimited field');
    }
    my $data = substr($$buf_ref, $$pos_ref, $len);
    $$pos_ref += $len;
    return $data;
}

sub _check_len {
    my ($buf_ref, $pos_ref, $need) = @_;
    if ($$pos_ref + $need > length($$buf_ref)) {
        ProtocolBuffers::PP::Error->throw('decode', "Truncated fixed field (need $need bytes)");
    }
}

1;

__END__

=head1 NAME

ProtocolBuffers::PP::Wire::Bytes - Fixed-width and length-delimited wire encoding

=head1 SYNOPSIS

    use ProtocolBuffers::PP::Wire::Bytes qw(
        encode_fixed32 decode_fixed32
        encode_double  decode_double
        encode_length_delimited decode_length_delimited
    );

    my $bytes = encode_fixed32(42);
    my $val   = decode_fixed32(\$buf, \$pos);

    my $ld = encode_length_delimited("hello");
    my $str = decode_length_delimited(\$buf, \$pos);

=head1 DESCRIPTION

Implements encoding and decoding for all protobuf fixed-width wire types
(fixed32, fixed64, sfixed32, sfixed64, float, double) and length-delimited
fields (strings, bytes, embedded messages).

All decode functions take a buffer reference and a position reference,
advancing the position past the consumed bytes.

=head1 FUNCTIONS

=head2 encode_fixed32($value) / decode_fixed32(\$buf, \$pos)

Unsigned 32-bit little-endian integer.

=head2 encode_fixed64($value) / decode_fixed64(\$buf, \$pos)

Unsigned 64-bit little-endian integer.

=head2 encode_sfixed32($value) / decode_sfixed32(\$buf, \$pos)

Signed 32-bit little-endian integer.

=head2 encode_sfixed64($value) / decode_sfixed64(\$buf, \$pos)

Signed 64-bit little-endian integer.

=head2 encode_float($value) / decode_float(\$buf, \$pos)

IEEE 754 single-precision (32-bit) float, little-endian.

=head2 encode_double($value) / decode_double(\$buf, \$pos)

IEEE 754 double-precision (64-bit) float, little-endian.

=head2 encode_length_delimited($data)

Prepends a varint-encoded length to C<$data>. Handles Perl's UTF-8 flag
by encoding character strings to bytes before measuring length.

=head2 decode_length_delimited(\$buf, \$pos)

Reads a varint length prefix then extracts that many bytes. Throws a
L<ProtocolBuffers::PP::Error> on truncation.

=head1 SEE ALSO

L<ProtocolBuffers::PP::Wire>, L<ProtocolBuffers::PP::Wire::Varint>

=cut
