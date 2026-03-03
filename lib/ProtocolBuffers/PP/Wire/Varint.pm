package ProtocolBuffers::PP::Wire::Varint;
use strict;
use warnings;
use ProtocolBuffers::PP::Error;

use Exporter 'import';
our @EXPORT_OK = qw(encode_varint decode_varint);

sub encode_varint {
    my ($val) = @_;
    $val = 0 unless defined $val && $val ne '';
    # Handle negative values: two's complement as uint64
    if ($val < 0) {
        $val = unpack("Q<", pack("q<", $val));
    }
    my $buf = '';
    while ($val > 0x7F) {
        $buf .= chr(($val & 0x7F) | 0x80);
        $val >>= 7;
    }
    $buf .= chr($val & 0x7F);
    return $buf;
}

sub decode_varint {
    my ($buf_ref, $pos_ref) = @_;
    my $result = 0;
    my $shift = 0;
    my $len = length($$buf_ref);
    while (1) {
        if ($$pos_ref >= $len) {
            ProtocolBuffers::PP::Error->throw('decode', 'Truncated varint');
        }
        my $byte = ord(substr($$buf_ref, $$pos_ref, 1));
        $$pos_ref++;
        $result |= ($byte & 0x7F) << $shift;
        if (($byte & 0x80) == 0) {
            return $result;
        }
        $shift += 7;
        if ($shift >= 64) {
            ProtocolBuffers::PP::Error->throw('decode', 'Varint too long');
        }
    }
}

1;

__END__

=head1 NAME

ProtocolBuffers::PP::Wire::Varint - Variable-length integer encoding/decoding

=head1 SYNOPSIS

    use ProtocolBuffers::PP::Wire::Varint qw(encode_varint decode_varint);

    my $bytes = encode_varint(300);        # "\xac\x02"
    my $val   = decode_varint(\$buf, \$pos);

=head1 DESCRIPTION

Implements the Protocol Buffers base-128 varint encoding. Negative values are
encoded as 10-byte two's complement unsigned 64-bit integers.

=head1 FUNCTIONS

=head2 encode_varint($value)

Encodes an integer as a varint byte string. Negative values are converted to
their unsigned 64-bit two's complement representation before encoding.

=head2 decode_varint(\$buffer, \$position)

Decodes a varint from C<$buffer> starting at C<$position>. Advances
C<$position> past the consumed bytes. Throws a
L<ProtocolBuffers::PP::Error> on truncation or if the varint exceeds 64 bits.

=head1 SEE ALSO

L<ProtocolBuffers::PP::Wire>, L<ProtocolBuffers::PP::Wire::ZigZag>

=cut
