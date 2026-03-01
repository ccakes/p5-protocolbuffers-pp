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
