package ProtocolBuffers::PP::Wire::ZigZag;
use strict;
use warnings;
no warnings 'portable';  # suppress hex > 0xffffffff warnings

use Exporter 'import';
our @EXPORT_OK = qw(zigzag_encode zigzag_decode);

sub zigzag_encode {
    my ($val) = @_;
    $val = 0 unless defined $val && $val ne '';
    # ($val << 1) ^ ($val >> 63) where >> is arithmetic right shift
    # Perl's >> is logical, so we compute sign-extend manually:
    # if negative, sign mask = 0xFFFFFFFFFFFFFFFF (-1), else 0
    my $sign_mask = ($val < 0) ? 0xFFFFFFFFFFFFFFFF : 0;
    return (($val << 1) ^ $sign_mask) & 0xFFFFFFFFFFFFFFFF;
}

sub zigzag_decode {
    my ($val) = @_;
    # ($val >> 1) ^ (-($val & 1))
    my $result = ($val >> 1) ^ (-($val & 1));
    return unpack("q<", pack("Q<", $result));
}

1;

__END__

=head1 NAME

ProtocolBuffers::PP::Wire::ZigZag - ZigZag encoding for signed integers

=head1 SYNOPSIS

    use ProtocolBuffers::PP::Wire::ZigZag qw(zigzag_encode zigzag_decode);

    my $encoded = zigzag_encode(-1);   # 1
    my $decoded = zigzag_decode(1);    # -1

=head1 DESCRIPTION

Implements ZigZag encoding used by protobuf C<sint32> and C<sint64> types.
ZigZag maps signed integers to unsigned integers so that small absolute values
have small encoded representations (unlike standard two's complement, where -1
encodes as a 10-byte varint).

=head1 FUNCTIONS

=head2 zigzag_encode($value)

Encodes a signed integer using ZigZag mapping:
C<0 E<rarr> 0, -1 E<rarr> 1, 1 E<rarr> 2, -2 E<rarr> 3, ...>

=head2 zigzag_decode($value)

Decodes a ZigZag-encoded unsigned integer back to its signed value.

=head1 SEE ALSO

L<ProtocolBuffers::PP::Wire::Varint>

=cut
