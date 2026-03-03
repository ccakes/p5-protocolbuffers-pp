package ProtocolBuffers::PP::Types;
use strict;
use warnings;
use ProtocolBuffers::PP::Wire;

use Exporter 'import';
our @EXPORT_OK = qw(
    TYPE_DOUBLE TYPE_FLOAT TYPE_INT64 TYPE_UINT64 TYPE_INT32
    TYPE_FIXED64 TYPE_FIXED32 TYPE_BOOL TYPE_STRING TYPE_GROUP
    TYPE_MESSAGE TYPE_BYTES TYPE_UINT32 TYPE_ENUM TYPE_SFIXED32
    TYPE_SFIXED64 TYPE_SINT32 TYPE_SINT64
    LABEL_OPTIONAL LABEL_REQUIRED LABEL_REPEATED
    wire_type_for_field_type
);

# FieldDescriptorProto.Type values
use constant {
    TYPE_DOUBLE   => 1,
    TYPE_FLOAT    => 2,
    TYPE_INT64    => 3,
    TYPE_UINT64   => 4,
    TYPE_INT32    => 5,
    TYPE_FIXED64  => 6,
    TYPE_FIXED32  => 7,
    TYPE_BOOL     => 8,
    TYPE_STRING   => 9,
    TYPE_GROUP    => 10,
    TYPE_MESSAGE  => 11,
    TYPE_BYTES    => 12,
    TYPE_UINT32   => 13,
    TYPE_ENUM     => 14,
    TYPE_SFIXED32 => 15,
    TYPE_SFIXED64 => 16,
    TYPE_SINT32   => 17,
    TYPE_SINT64   => 18,
};

# FieldDescriptorProto.Label values
use constant {
    LABEL_OPTIONAL => 1,
    LABEL_REQUIRED => 2,
    LABEL_REPEATED => 3,
};

my %WIRE_TYPE_MAP = (
    TYPE_DOUBLE()   => ProtocolBuffers::PP::Wire::FIXED64,
    TYPE_FLOAT()    => ProtocolBuffers::PP::Wire::FIXED32,
    TYPE_INT64()    => ProtocolBuffers::PP::Wire::VARINT,
    TYPE_UINT64()   => ProtocolBuffers::PP::Wire::VARINT,
    TYPE_INT32()    => ProtocolBuffers::PP::Wire::VARINT,
    TYPE_FIXED64()  => ProtocolBuffers::PP::Wire::FIXED64,
    TYPE_FIXED32()  => ProtocolBuffers::PP::Wire::FIXED32,
    TYPE_BOOL()     => ProtocolBuffers::PP::Wire::VARINT,
    TYPE_STRING()   => ProtocolBuffers::PP::Wire::LENGTH_DELIMITED,
    TYPE_GROUP()    => ProtocolBuffers::PP::Wire::START_GROUP,
    TYPE_MESSAGE()  => ProtocolBuffers::PP::Wire::LENGTH_DELIMITED,
    TYPE_BYTES()    => ProtocolBuffers::PP::Wire::LENGTH_DELIMITED,
    TYPE_UINT32()   => ProtocolBuffers::PP::Wire::VARINT,
    TYPE_ENUM()     => ProtocolBuffers::PP::Wire::VARINT,
    TYPE_SFIXED32() => ProtocolBuffers::PP::Wire::FIXED32,
    TYPE_SFIXED64() => ProtocolBuffers::PP::Wire::FIXED64,
    TYPE_SINT32()   => ProtocolBuffers::PP::Wire::VARINT,
    TYPE_SINT64()   => ProtocolBuffers::PP::Wire::VARINT,
);

sub wire_type_for_field_type {
    my ($type) = @_;
    return $WIRE_TYPE_MAP{$type};
}

1;

__END__

=head1 NAME

ProtocolBuffers::PP::Types - Protocol Buffers field type and label constants

=head1 SYNOPSIS

    use ProtocolBuffers::PP::Types qw(
        TYPE_INT32 TYPE_STRING TYPE_MESSAGE LABEL_REPEATED
        wire_type_for_field_type
    );

    my $wire_type = wire_type_for_field_type(TYPE_INT32);

=head1 DESCRIPTION

Defines constants corresponding to C<FieldDescriptorProto.Type> and
C<FieldDescriptorProto.Label> values from the Protocol Buffers specification,
plus a mapping function from field types to wire types.

=head1 CONSTANTS

=head2 Field Types

    TYPE_DOUBLE   (1)    TYPE_FLOAT    (2)    TYPE_INT64    (3)
    TYPE_UINT64   (4)    TYPE_INT32    (5)    TYPE_FIXED64  (6)
    TYPE_FIXED32  (7)    TYPE_BOOL     (8)    TYPE_STRING   (9)
    TYPE_GROUP    (10)   TYPE_MESSAGE  (11)   TYPE_BYTES    (12)
    TYPE_UINT32   (13)   TYPE_ENUM     (14)   TYPE_SFIXED32 (15)
    TYPE_SFIXED64 (16)   TYPE_SINT32   (17)   TYPE_SINT64   (18)

=head2 Labels

    LABEL_OPTIONAL (1)   LABEL_REQUIRED (2)   LABEL_REPEATED (3)

=head1 FUNCTIONS

=head2 wire_type_for_field_type($type)

Returns the protobuf wire type constant for a given field type.

=head1 SEE ALSO

L<ProtocolBuffers::PP::Wire>, L<ProtocolBuffers::PP::Util>

=cut
