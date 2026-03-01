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
