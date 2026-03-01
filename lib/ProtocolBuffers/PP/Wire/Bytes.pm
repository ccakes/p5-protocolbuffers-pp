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
