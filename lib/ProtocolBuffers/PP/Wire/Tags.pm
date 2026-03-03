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

__END__

=head1 NAME

ProtocolBuffers::PP::Wire::Tags - Field tag encoding/decoding

=head1 SYNOPSIS

    use ProtocolBuffers::PP::Wire::Tags qw(encode_tag decode_tag);

    my $bytes = encode_tag(1, ProtocolBuffers::PP::Wire::VARINT);
    my ($field_number, $wire_type) = decode_tag(\$buf, \$pos);

=head1 DESCRIPTION

Encodes and decodes protobuf field tags. A tag is a varint that packs the
field number (upper bits) and wire type (lower 3 bits).

=head1 FUNCTIONS

=head2 encode_tag($field_number, $wire_type)

Returns the varint-encoded tag bytes for the given field number and wire type.

=head2 decode_tag(\$buffer, \$position)

Decodes a tag from the buffer, advancing the position. Returns a
C<($field_number, $wire_type)> pair.

=head1 SEE ALSO

L<ProtocolBuffers::PP::Wire>, L<ProtocolBuffers::PP::Wire::Varint>

=cut
