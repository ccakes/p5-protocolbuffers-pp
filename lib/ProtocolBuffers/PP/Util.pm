package ProtocolBuffers::PP::Util;
use strict;
use warnings;
no warnings 'portable';
use ProtocolBuffers::PP::Types qw(
    TYPE_DOUBLE TYPE_FLOAT TYPE_INT64 TYPE_UINT64 TYPE_INT32
    TYPE_FIXED64 TYPE_FIXED32 TYPE_BOOL TYPE_STRING TYPE_GROUP
    TYPE_MESSAGE TYPE_BYTES TYPE_UINT32 TYPE_ENUM TYPE_SFIXED32
    TYPE_SFIXED64 TYPE_SINT32 TYPE_SINT64
);

use Exporter 'import';
our @EXPORT_OK = qw(default_value_for_type is_packable int32_to_signed int64_to_signed is_numeric_type);

sub default_value_for_type {
    my ($type) = @_;
    if ($type == TYPE_STRING) { return '' }
    if ($type == TYPE_BYTES)  { return '' }
    if ($type == TYPE_BOOL)   { return 0 }
    if ($type == TYPE_DOUBLE || $type == TYPE_FLOAT) { return 0.0 }
    if ($type == TYPE_MESSAGE) { return undef }
    if ($type == TYPE_GROUP)   { return undef }
    # All integer/enum types
    return 0;
}

sub is_packable {
    my ($type) = @_;
    return 0 if $type == TYPE_STRING;
    return 0 if $type == TYPE_BYTES;
    return 0 if $type == TYPE_MESSAGE;
    return 0 if $type == TYPE_GROUP;
    return 1;
}

sub is_numeric_type {
    my ($type) = @_;
    return is_packable($type);
}

sub int32_to_signed {
    my ($val) = @_;
    $val &= 0xFFFFFFFF;
    if ($val >= 0x80000000) {
        return $val - 0x100000000;
    }
    return $val;
}

sub int64_to_signed {
    my ($val) = @_;
    return unpack("q<", pack("Q<", $val));
}

1;

__END__

=head1 NAME

ProtocolBuffers::PP::Util - Utility functions for protobuf field handling

=head1 SYNOPSIS

    use ProtocolBuffers::PP::Util qw(
        default_value_for_type is_packable is_numeric_type
        int32_to_signed int64_to_signed
    );

    my $default = default_value_for_type(TYPE_STRING);  # ''
    my $can_pack = is_packable(TYPE_INT32);             # 1

=head1 DESCRIPTION

Helper functions used by the encoder, decoder, and JSON modules for
determining field defaults, packability, and signed integer conversion.

=head1 FUNCTIONS

=head2 default_value_for_type($type)

Returns the proto3 default value for a field type: empty string for
C<TYPE_STRING>/C<TYPE_BYTES>, C<0> for numeric/bool types, C<0.0> for
float/double, C<undef> for C<TYPE_MESSAGE>/C<TYPE_GROUP>.

=head2 is_packable($type)

Returns true if the field type can use packed repeated encoding (all types
except string, bytes, message, and group).

=head2 is_numeric_type($type)

Alias for C<is_packable>. Returns true for numeric field types.

=head2 int32_to_signed($val)

Converts an unsigned 32-bit integer to its signed two's complement
representation.

=head2 int64_to_signed($val)

Converts an unsigned 64-bit integer to its signed two's complement
representation using C<pack>/C<unpack>.

=head1 SEE ALSO

L<ProtocolBuffers::PP::Types>

=cut
