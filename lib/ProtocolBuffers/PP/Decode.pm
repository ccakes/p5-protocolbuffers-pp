package ProtocolBuffers::PP::Decode;
use strict;
use warnings;
use ProtocolBuffers::PP::Wire;
use ProtocolBuffers::PP::Wire::Varint qw(encode_varint decode_varint);
use ProtocolBuffers::PP::Wire::ZigZag qw(zigzag_decode);
use ProtocolBuffers::PP::Wire::Tags qw(encode_tag decode_tag);
use ProtocolBuffers::PP::Wire::Bytes qw(
    decode_fixed32 decode_fixed64
    decode_sfixed32 decode_sfixed64
    decode_float decode_double
    decode_length_delimited
);
use ProtocolBuffers::PP::Types qw(
    TYPE_DOUBLE TYPE_FLOAT TYPE_INT64 TYPE_UINT64 TYPE_INT32
    TYPE_FIXED64 TYPE_FIXED32 TYPE_BOOL TYPE_STRING TYPE_GROUP
    TYPE_MESSAGE TYPE_BYTES TYPE_UINT32 TYPE_ENUM TYPE_SFIXED32
    TYPE_SFIXED64 TYPE_SINT32 TYPE_SINT64
    LABEL_REPEATED
    wire_type_for_field_type
);
use ProtocolBuffers::PP::Util qw(default_value_for_type int32_to_signed int64_to_signed is_packable);
use ProtocolBuffers::PP::Error;

use Exporter 'import';
our @EXPORT_OK = qw(decode_message);

sub decode_message {
    my ($class_or_desc, $bytes, $descriptor) = @_;

    # If called as decode_message($descriptor, $bytes) with 2 args
    if (!defined $descriptor) {
        $descriptor = $class_or_desc;
    }

    my $msg = {};
    my $fields = $descriptor->{fields};

    # Initialize repeated fields and defaults
    for my $fn (keys %$fields) {
        my $fd = $fields->{$fn};
        if ($fd->{map_entry}) {
            $msg->{$fd->{name}} = {};
        } elsif ($fd->{label} == LABEL_REPEATED) {
            $msg->{$fd->{name}} = [];
        }
    }

    my $pos = 0;
    my $len = length($bytes);
    my $unknown_buf = '';

    while ($pos < $len) {
        my $tag_start = $pos;
        my ($field_number, $wire_type) = decode_tag(\$bytes, \$pos);

        if ($field_number == 0) {
            ProtocolBuffers::PP::Error->throw('decode', 'Invalid field number 0');
        }

        my $fd = $fields->{$field_number};

        if (!$fd) {
            # Unknown field — preserve raw bytes
            $unknown_buf .= _skip_and_capture(\$bytes, \$pos, $wire_type, $tag_start, $field_number);
            next;
        }

        my $expected_wt = wire_type_for_field_type($fd->{type});

        # Accept packed encoding for repeated numeric fields
        if ($fd->{label} == LABEL_REPEATED && is_packable($fd->{type})
            && $wire_type == ProtocolBuffers::PP::Wire::LENGTH_DELIMITED
            && $expected_wt != ProtocolBuffers::PP::Wire::LENGTH_DELIMITED) {
            # Packed repeated field
            my $packed_data = decode_length_delimited(\$bytes, \$pos);
            my $ppos = 0;
            my $plen = length($packed_data);
            while ($ppos < $plen) {
                my $val = _decode_scalar_value(\$packed_data, \$ppos, $fd->{type});
                push @{$msg->{$fd->{name}}}, $val;
            }
            next;
        }

        # Wire type validation
        if ($wire_type != $expected_wt) {
            # Groups: accept START_GROUP for group fields
            unless ($fd->{type} == TYPE_GROUP && $wire_type == ProtocolBuffers::PP::Wire::START_GROUP) {
                ProtocolBuffers::PP::Error->throw('decode',
                    "Wire type mismatch for field $field_number: expected $expected_wt, got $wire_type");
            }
        }

        my $value = _decode_field_value(\$bytes, \$pos, $fd, $wire_type, $field_number);

        # Map field
        if ($fd->{map_entry}) {
            my ($k, $v) = _decode_map_entry($value, $fd);
            $msg->{$fd->{name}}{$k} = $v;
            next;
        }

        # Repeated field
        if ($fd->{label} == LABEL_REPEATED) {
            push @{$msg->{$fd->{name}}}, $value;
            next;
        }

        # Oneof tracking
        if (defined $fd->{oneof_index}) {
            # Clear other oneof members
            my $oneof = $descriptor->{oneofs}[$fd->{oneof_index}];
            if ($oneof) {
                for my $ofn (@{$oneof->{fields}}) {
                    next if $ofn == $field_number;
                    my $ofd = $fields->{$ofn};
                    $msg->{$ofd->{name}} = undef if $ofd;
                }
            }
            $msg->{_oneof_case} ||= {};
            $msg->{_oneof_case}{$fd->{oneof_index}} = $field_number;
        }

        # Message merging: if we see a message field again, merge
        if ($fd->{type} == TYPE_MESSAGE && defined $msg->{$fd->{name}} && ref $msg->{$fd->{name}} eq 'HASH') {
            _merge_message($msg->{$fd->{name}}, $value, $fd->{message_descriptor});
            next;
        }

        $msg->{$fd->{name}} = $value;
    }

    if ($unknown_buf ne '') {
        $msg->{_unknown_fields} = $unknown_buf;
    }

    return $msg;
}

sub _decode_field_value {
    my ($buf_ref, $pos_ref, $fd, $wire_type, $field_number) = @_;

    if ($fd->{type} == TYPE_MESSAGE) {
        my $data = decode_length_delimited($buf_ref, $pos_ref);
        return decode_message($fd->{message_descriptor}, $data, $fd->{message_descriptor});
    }

    if ($fd->{type} == TYPE_GROUP) {
        return _decode_group($buf_ref, $pos_ref, $fd, $field_number);
    }

    return _decode_scalar_value($buf_ref, $pos_ref, $fd->{type});
}

sub _decode_scalar_value {
    my ($buf_ref, $pos_ref, $type) = @_;

    if ($type == TYPE_DOUBLE)   { return decode_double($buf_ref, $pos_ref) }
    if ($type == TYPE_FLOAT)    { return decode_float($buf_ref, $pos_ref) }
    if ($type == TYPE_INT64)    { return int64_to_signed(decode_varint($buf_ref, $pos_ref)) }
    if ($type == TYPE_UINT64)   { return decode_varint($buf_ref, $pos_ref) }
    if ($type == TYPE_INT32)    { return int32_to_signed(decode_varint($buf_ref, $pos_ref)) }
    if ($type == TYPE_FIXED64)  { return decode_fixed64($buf_ref, $pos_ref) }
    if ($type == TYPE_FIXED32)  { return decode_fixed32($buf_ref, $pos_ref) }
    if ($type == TYPE_BOOL)     { return decode_varint($buf_ref, $pos_ref) ? 1 : 0 }
    if ($type == TYPE_STRING) {
        my $str = decode_length_delimited($buf_ref, $pos_ref);
        utf8::decode($str);  # Mark as Perl character string for proper JSON handling
        return $str;
    }
    if ($type == TYPE_BYTES)    { return decode_length_delimited($buf_ref, $pos_ref) }
    if ($type == TYPE_UINT32)   { return decode_varint($buf_ref, $pos_ref) & 0xFFFFFFFF }
    if ($type == TYPE_ENUM)     { return int32_to_signed(decode_varint($buf_ref, $pos_ref)) }
    if ($type == TYPE_SFIXED32) { return decode_sfixed32($buf_ref, $pos_ref) }
    if ($type == TYPE_SFIXED64) { return decode_sfixed64($buf_ref, $pos_ref) }
    if ($type == TYPE_SINT32)   { return zigzag_decode(decode_varint($buf_ref, $pos_ref) & 0xFFFFFFFF) }
    if ($type == TYPE_SINT64)   { return zigzag_decode(decode_varint($buf_ref, $pos_ref)) }

    die "Unknown type: $type";
}

sub _decode_group {
    my ($buf_ref, $pos_ref, $fd, $field_number) = @_;
    # Collect bytes until END_GROUP for this field number
    my $group_bytes = '';
    while (1) {
        my $tag_start = $$pos_ref;
        my ($fn, $wt) = decode_tag($buf_ref, $pos_ref);
        if ($wt == ProtocolBuffers::PP::Wire::END_GROUP && $fn == $field_number) {
            last;
        }
        # Re-parse as part of group body
        $$pos_ref = $tag_start;
        my $before = $$pos_ref;
        # Skip this field and capture its bytes
        ($fn, $wt) = decode_tag($buf_ref, $pos_ref);
        my $captured = _skip_field($buf_ref, $pos_ref, $wt, $fn);
        $group_bytes .= substr($$buf_ref, $before, $$pos_ref - $before);
    }
    return decode_message($fd->{message_descriptor}, $group_bytes, $fd->{message_descriptor});
}

sub _skip_and_capture {
    my ($buf_ref, $pos_ref, $wire_type, $tag_start, $field_number) = @_;
    _skip_field($buf_ref, $pos_ref, $wire_type, $field_number);
    return substr($$buf_ref, $tag_start, $$pos_ref - $tag_start);
}

sub _skip_field {
    my ($buf_ref, $pos_ref, $wire_type, $field_number) = @_;
    if ($wire_type == ProtocolBuffers::PP::Wire::VARINT) {
        decode_varint($buf_ref, $pos_ref);
    } elsif ($wire_type == ProtocolBuffers::PP::Wire::FIXED64) {
        if ($$pos_ref + 8 > length($$buf_ref)) {
            ProtocolBuffers::PP::Error->throw('decode', 'Truncated fixed64');
        }
        $$pos_ref += 8;
    } elsif ($wire_type == ProtocolBuffers::PP::Wire::LENGTH_DELIMITED) {
        my $len = decode_varint($buf_ref, $pos_ref);
        if ($$pos_ref + $len > length($$buf_ref)) {
            ProtocolBuffers::PP::Error->throw('decode', 'Truncated length-delimited');
        }
        $$pos_ref += $len;
    } elsif ($wire_type == ProtocolBuffers::PP::Wire::START_GROUP) {
        # Skip until END_GROUP
        while (1) {
            my ($fn, $wt) = decode_tag($buf_ref, $pos_ref);
            if ($wt == ProtocolBuffers::PP::Wire::END_GROUP && $fn == $field_number) {
                last;
            }
            _skip_field($buf_ref, $pos_ref, $wt, $fn);
        }
    } elsif ($wire_type == ProtocolBuffers::PP::Wire::FIXED32) {
        if ($$pos_ref + 4 > length($$buf_ref)) {
            ProtocolBuffers::PP::Error->throw('decode', 'Truncated fixed32');
        }
        $$pos_ref += 4;
    } else {
        ProtocolBuffers::PP::Error->throw('decode', "Unknown wire type: $wire_type");
    }
}

sub _decode_map_entry {
    my ($entry_msg, $fd) = @_;
    my $me = $fd->{map_entry};

    # Default key/value — use proper type defaults (0 for integers, '' for strings)
    my $key = default_value_for_type($me->{key_type});
    $key = '' unless defined $key;  # fallback
    my $value = default_value_for_type($me->{value_type});

    # Build a mini-descriptor for the map entry
    my $entry_desc = {
        full_name => 'MapEntry',
        syntax => 'proto3',
        fields => {
            1 => { name => 'key',   number => 1, type => $me->{key_type},   label => 1, packed => 0, oneof_index => undef },
            2 => { name => 'value', number => 2, type => $me->{value_type}, label => 1, packed => 0, oneof_index => undef,
                    message_descriptor => $me->{value_message_descriptor} },
        },
        oneofs => [],
        is_map_entry => 1,
    };

    # entry_msg is already a decoded sub-message (from LENGTH_DELIMITED)
    # But we got the raw bytes, so we need the caller to pass us the hash
    # Actually, _decode_field_value returns decoded message for TYPE_MESSAGE
    # But map entries are TYPE_MESSAGE, so entry_msg is the decoded hash
    # Wait - the caller passes the raw value from _decode_field_value which
    # returns a hash. But we're being called with the bytes from decode_length_delimited...
    # Let me trace: in decode_message, when we see a map field, we call _decode_field_value
    # which for TYPE_MESSAGE calls decode_length_delimited + decode_message. But the map
    # entry's descriptor is the field's message_descriptor. So entry_msg is the decoded hash.

    # Actually no - looking at decode_message flow: the field type is TYPE_MESSAGE,
    # so _decode_field_value decodes it using fd->message_descriptor.
    # But for map entries, we need the map entry descriptor.
    # The fd->message_descriptor should already be the map entry descriptor.

    $key = $entry_msg->{key} if defined $entry_msg->{key};
    $value = $entry_msg->{value};

    return ($key, $value);
}

sub _merge_message {
    my ($existing, $new, $descriptor) = @_;
    return unless $descriptor;
    my $fields = $descriptor->{fields};
    for my $fn (keys %$fields) {
        my $fd = $fields->{$fn};
        my $name = $fd->{name};
        next unless exists $new->{$name} && defined $new->{$name};

        if ($fd->{map_entry} && ref $existing->{$name} eq 'HASH' && ref $new->{$name} eq 'HASH') {
            # Merge maps
            for my $k (keys %{$new->{$name}}) {
                $existing->{$name}{$k} = $new->{$name}{$k};
            }
        } elsif ($fd->{label} == LABEL_REPEATED && ref $existing->{$name} eq 'ARRAY') {
            push @{$existing->{$name}}, @{$new->{$name}};
        } elsif ($fd->{type} == TYPE_MESSAGE && ref $existing->{$name} eq 'HASH' && ref $new->{$name} eq 'HASH') {
            _merge_message($existing->{$name}, $new->{$name}, $fd->{message_descriptor});
        } else {
            $existing->{$name} = $new->{$name};
        }
    }
    # Merge unknown fields
    if ($new->{_unknown_fields}) {
        $existing->{_unknown_fields} = ($existing->{_unknown_fields} || '') . $new->{_unknown_fields};
    }
}

1;
