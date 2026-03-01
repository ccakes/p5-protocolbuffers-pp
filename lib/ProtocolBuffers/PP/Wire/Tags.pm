package ProtocolBuffers::PP::Wire::Tags;
use strict;
use warnings;
use ProtocolBuffers::PP::Wire::Varint qw(encode_varint decode_varint);

use Exporter 'import';
our @EXPORT_OK = qw(encode_tag decode_tag);

sub encode_tag {
    my ($field_number, $wire_type) = @_;
    return encode_varint(($field_number << 3) | $wire_type);
}

sub decode_tag {
    my ($buf_ref, $pos_ref) = @_;
    my $val = decode_varint($buf_ref, $pos_ref);
    my $wire_type = $val & 0x07;
    my $field_number = $val >> 3;
    return ($field_number, $wire_type);
}

1;
