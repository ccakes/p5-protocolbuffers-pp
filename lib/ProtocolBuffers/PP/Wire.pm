package ProtocolBuffers::PP::Wire;
use strict;
use warnings;

use constant {
    VARINT          => 0,
    FIXED64         => 1,
    LENGTH_DELIMITED => 2,
    START_GROUP     => 3,
    END_GROUP       => 4,
    FIXED32         => 5,
};

1;

__END__

=head1 NAME

ProtocolBuffers::PP::Wire - Wire type constants for the protobuf binary format

=head1 SYNOPSIS

    use ProtocolBuffers::PP::Wire;

    my $wt = ProtocolBuffers::PP::Wire::VARINT;  # 0

=head1 DESCRIPTION

Defines the six wire type constants used in the Protocol Buffers binary
encoding format.

=head1 CONSTANTS

    VARINT           (0)  - Variable-length integers
    FIXED64          (1)  - 64-bit fixed-width values
    LENGTH_DELIMITED (2)  - Length-prefixed bytes
    START_GROUP      (3)  - Start of a group (deprecated)
    END_GROUP        (4)  - End of a group (deprecated)
    FIXED32          (5)  - 32-bit fixed-width values

=head1 SEE ALSO

L<ProtocolBuffers::PP::Wire::Varint>, L<ProtocolBuffers::PP::Wire::Bytes>,
L<ProtocolBuffers::PP::Wire::Tags>, L<ProtocolBuffers::PP::Types>

=cut
