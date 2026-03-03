package ProtocolBuffers::PP::Encode;
use strict;
use warnings;
use ProtocolBuffers::PP::Wire;
use ProtocolBuffers::PP::Wire::Varint qw(encode_varint);
use ProtocolBuffers::PP::Wire::ZigZag qw(zigzag_encode);
use ProtocolBuffers::PP::Wire::Tags qw(encode_tag);
use ProtocolBuffers::PP::Wire::Bytes qw(
    encode_fixed32 encode_fixed64
    encode_sfixed32 encode_sfixed64
    encode_float encode_double
    encode_length_delimited
);
use ProtocolBuffers::PP::Types qw(
    TYPE_DOUBLE TYPE_FLOAT TYPE_INT64 TYPE_UINT64 TYPE_INT32
    TYPE_FIXED64 TYPE_FIXED32 TYPE_BOOL TYPE_STRING TYPE_GROUP
    TYPE_MESSAGE TYPE_BYTES TYPE_UINT32 TYPE_ENUM TYPE_SFIXED32
    TYPE_SFIXED64 TYPE_SINT32 TYPE_SINT64
    LABEL_REPEATED
    wire_type_for_field_type
);
use ProtocolBuffers::PP::Util qw(default_value_for_type is_packable);

use Exporter 'import';
our @EXPORT_OK = qw(encode_message encode_scalar_value);

sub encode_message {
    my ($msg, $descriptor) = @_;
    my $buf = '';
    return $buf unless ref $msg;
    my $fields = $descriptor->{fields};

    # Encode fields in field number order for determinism
    for my $fn (sort { $a <=> $b } keys %$fields) {
        my $fd = $fields->{$fn};
        my $name = $fd->{name};
        my $value = $msg->{$name};

        # Handle map fields
        if ($fd->{map_entry}) {
            next unless defined $value && ref $value eq 'HASH' && %$value;
            my $me = $fd->{map_entry};
            for my $k (sort keys %$value) {
                my $entry_buf = _encode_map_entry($k, $value->{$k}, $me, $fd);
                $buf .= encode_tag($fn, ProtocolBuffers::PP::Wire::LENGTH_DELIMITED);
                $buf .= encode_length_delimited($entry_buf);
            }
            next;
        }

        # Handle repeated fields
        if ($fd->{label} == LABEL_REPEATED) {
            next unless defined $value && ref $value eq 'ARRAY' && @$value;
            if ($fd->{packed} && is_packable($fd->{type})) {
                # Packed encoding
                my $packed_buf = '';
                for my $elem (@$value) {
                    $packed_buf .= _encode_scalar($elem, $fd->{type}, $fd);
                }
                $buf .= encode_tag($fn, ProtocolBuffers::PP::Wire::LENGTH_DELIMITED);
                $buf .= encode_length_delimited($packed_buf);
            } else {
                # Unpacked repeated
                for my $elem (@$value) {
                    $buf .= _encode_field($fn, $elem, $fd);
                }
            }
            next;
        }

        # Handle oneof: check if this field is active
        if (defined $fd->{oneof_index}) {
            my $active = $msg->{_oneof_case} && $msg->{_oneof_case}{$fd->{oneof_index}};
            next unless defined $active && $active == $fn;
        }

        # Singular field
        next unless defined $value;

        # Proto3 default omission (non-oneof, non-proto3_optional)
        if (($descriptor->{syntax} || 'proto3') eq 'proto3'
            && !$fd->{proto3_optional}
            && !defined $fd->{oneof_index}) {
            my $def = default_value_for_type($fd->{type});
            if (defined $def) {
                if ($fd->{type} == TYPE_DOUBLE || $fd->{type} == TYPE_FLOAT) {
                    next if $value == 0 && !_is_negative_zero($value);
                } elsif ($fd->{type} == TYPE_BOOL) {
                    next if !$value;
                } elsif ($fd->{type} == TYPE_STRING || $fd->{type} == TYPE_BYTES) {
                    next if $value eq '';
                } elsif ($fd->{type} == TYPE_MESSAGE) {
                    # messages are always emitted if set
                } else {
                    next if $value == 0;
                }
            }
        }

        $buf .= _encode_field($fn, $value, $fd);
    }

    # Append unknown fields
    if ($msg->{_unknown_fields}) {
        $buf .= $msg->{_unknown_fields};
    }

    return $buf;
}

sub _is_negative_zero {
    my ($val) = @_;
    return ($val == 0 && sprintf("%g", $val) eq '-0');
}

sub _encode_field {
    my ($fn, $value, $fd) = @_;
    my $type = $fd->{type};

    if ($type == TYPE_MESSAGE) {
        my $sub_desc = $fd->{message_descriptor};
        my $encoded = encode_message($value, $sub_desc);
        return encode_tag($fn, ProtocolBuffers::PP::Wire::LENGTH_DELIMITED)
             . encode_length_delimited($encoded);
    }

    if ($type == TYPE_GROUP) {
        my $sub_desc = $fd->{message_descriptor};
        my $encoded = encode_message($value, $sub_desc);
        return encode_tag($fn, ProtocolBuffers::PP::Wire::START_GROUP)
             . $encoded
             . encode_tag($fn, ProtocolBuffers::PP::Wire::END_GROUP);
    }

    my $wt = wire_type_for_field_type($type);
    return encode_tag($fn, $wt) . _encode_scalar($value, $type, $fd);
}

sub _encode_scalar {
    my ($value, $type, $fd) = @_;
    if ($type == TYPE_DOUBLE)   { return encode_double($value) }
    if ($type == TYPE_FLOAT)    { return encode_float($value) }
    if ($type == TYPE_INT64)    { return encode_varint($value) }
    if ($type == TYPE_UINT64)   { return encode_varint($value) }
    if ($type == TYPE_INT32) {
        # Negative int32 must be sign-extended to 10-byte varint
        return encode_varint($value);
    }
    if ($type == TYPE_FIXED64)  { return encode_fixed64($value) }
    if ($type == TYPE_FIXED32)  { return encode_fixed32($value) }
    if ($type == TYPE_BOOL)     { return encode_varint($value ? 1 : 0) }
    if ($type == TYPE_STRING)   { return encode_length_delimited($value) }
    if ($type == TYPE_BYTES)    { return encode_length_delimited($value) }
    if ($type == TYPE_UINT32)   { return encode_varint($value) }
    if ($type == TYPE_ENUM)     { return encode_varint($value) }
    if ($type == TYPE_SFIXED32) { return encode_sfixed32($value) }
    if ($type == TYPE_SFIXED64) { return encode_sfixed64($value) }
    if ($type == TYPE_SINT32)   { return encode_varint(zigzag_encode($value)) }
    if ($type == TYPE_SINT64)   { return encode_varint(zigzag_encode($value)) }
    die "Unknown type: $type";
}

sub encode_scalar_value {
    my ($value, $type) = @_;
    return _encode_scalar($value, $type, {});
}

sub _encode_map_entry {
    my ($key, $value, $map_entry, $fd) = @_;
    my $buf = '';

    # Key is field 1
    my $key_type = $map_entry->{key_type};
    my $key_wt = wire_type_for_field_type($key_type);
    $buf .= encode_tag(1, $key_wt);
    $buf .= _encode_scalar($key, $key_type, {});

    # Value is field 2
    my $val_type = $map_entry->{value_type};
    if ($val_type == TYPE_MESSAGE) {
        my $sub_desc = $map_entry->{value_message_descriptor}
                    || $fd->{message_descriptor};
        my $encoded = encode_message($value, $sub_desc);
        $buf .= encode_tag(2, ProtocolBuffers::PP::Wire::LENGTH_DELIMITED);
        $buf .= encode_length_delimited($encoded);
    } else {
        my $val_wt = wire_type_for_field_type($val_type);
        $buf .= encode_tag(2, $val_wt);
        $buf .= _encode_scalar($value, $val_type, {});
    }

    return $buf;
}

1;

__END__

=head1 NAME

ProtocolBuffers::PP::Encode - Descriptor-driven protobuf binary encoder

=head1 SYNOPSIS

    use ProtocolBuffers::PP::Encode qw(encode_message encode_scalar_value);

    my $bytes = encode_message($msg_hash, $descriptor);

    # Encode a single scalar value (for map entries, etc.)
    my $bytes = encode_scalar_value($value, TYPE_INT32);

=head1 DESCRIPTION

Encodes a Perl hash into Protocol Buffers binary wire format using a message
descriptor. Handles all field types including singular, repeated (packed and
unpacked), oneof, map, and group fields.

Fields are encoded in field number order for deterministic output. Proto3
default value omission is applied to non-oneof, non-optional singular fields.
Unknown fields stored in C<_unknown_fields> are appended to preserve
round-trip fidelity.

=head1 FUNCTIONS

=head2 encode_message($msg, $descriptor)

Encodes a message hash into binary protobuf bytes using the given descriptor.
Returns a byte string.

=head2 encode_scalar_value($value, $type)

Encodes a single scalar value for the given field type. Does not include a
field tag. Useful for encoding individual values outside a full message context.

=head1 SEE ALSO

L<ProtocolBuffers::PP::Decode>, L<ProtocolBuffers::PP::Types>,
L<ProtocolBuffers::PP::Wire>

=cut
