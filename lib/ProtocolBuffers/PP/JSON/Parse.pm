package ProtocolBuffers::PP::JSON::Parse;
use strict;
use warnings;
no warnings 'portable';
use JSON::PP;
use MIME::Base64 ();
use B ();
use ProtocolBuffers::PP::Types qw(
    TYPE_DOUBLE TYPE_FLOAT TYPE_INT64 TYPE_UINT64 TYPE_INT32
    TYPE_FIXED64 TYPE_FIXED32 TYPE_BOOL TYPE_STRING TYPE_GROUP
    TYPE_MESSAGE TYPE_BYTES TYPE_UINT32 TYPE_ENUM TYPE_SFIXED32
    TYPE_SFIXED64 TYPE_SINT32 TYPE_SINT64
    LABEL_REPEATED
);
use ProtocolBuffers::PP::Timestamp qw(string_to_timestamp);
use ProtocolBuffers::PP::Duration qw(string_to_duration);
use ProtocolBuffers::PP::FieldMask qw(string_to_field_mask);
use ProtocolBuffers::PP::Error;

use Exporter 'import';
our @EXPORT_OK = qw(parse_message);

my $json_pp = JSON::PP->new->allow_nonref(1)->utf8(1);

# WKT dispatch table
my %WKT_PARSERS = (
    'google.protobuf.Timestamp' => \&_parse_timestamp,
    'google.protobuf.Duration'  => \&_parse_duration,
    'google.protobuf.FieldMask' => \&_parse_field_mask,
    'google.protobuf.Any'       => \&_parse_any,
    'google.protobuf.Struct'    => \&_parse_struct,
    'google.protobuf.Value'     => \&_parse_value,
    'google.protobuf.ListValue' => \&_parse_list_value,
    'google.protobuf.BoolValue'   => \&_parse_wrapper,
    'google.protobuf.Int32Value'  => \&_parse_wrapper,
    'google.protobuf.Int64Value'  => \&_parse_wrapper,
    'google.protobuf.UInt32Value' => \&_parse_wrapper,
    'google.protobuf.UInt64Value' => \&_parse_wrapper,
    'google.protobuf.FloatValue'  => \&_parse_wrapper,
    'google.protobuf.DoubleValue' => \&_parse_wrapper,
    'google.protobuf.StringValue' => \&_parse_wrapper,
    'google.protobuf.BytesValue'  => \&_parse_wrapper,
);

sub parse_message {
    my ($json_str, $descriptor, %opts) = @_;

    my $data;
    if (ref $json_str) {
        $data = $json_str;
    } else {
        # JSON::PP with utf8(1) expects raw UTF-8 bytes, not Perl character strings
        utf8::encode($json_str) if utf8::is_utf8($json_str);
        eval { $data = $json_pp->decode($json_str) };
        if ($@) {
            ProtocolBuffers::PP::Error->throw('json', "Invalid JSON: $@");
        }
    }

    my $full_name = $descriptor->{full_name} || '';
    if (my $parser = $WKT_PARSERS{$full_name}) {
        return $parser->($data, $descriptor, %opts);
    }

    unless (ref $data eq 'HASH') {
        ProtocolBuffers::PP::Error->throw('json', 'Expected JSON object for message');
    }

    return _parse_hash($data, $descriptor, %opts);
}

sub _parse_hash {
    my ($data, $descriptor, %opts) = @_;
    my $fields = $descriptor->{fields};
    my $by_json = $descriptor->{fields_by_json_name} || {};
    my $by_name = $descriptor->{fields_by_name} || {};
    my $ignore_unknown = $opts{ignore_unknown_fields} || 0;
    my $msg = {};

    # Initialize repeated fields
    for my $fn (keys %$fields) {
        my $fd = $fields->{$fn};
        if ($fd->{map_entry}) {
            $msg->{$fd->{name}} = {};
        } elsif ($fd->{label} == LABEL_REPEATED) {
            $msg->{$fd->{name}} = [];
        }
    }

    for my $key (keys %$data) {
        # Look up field by json_name first, then by name
        my $fn = $by_json->{$key} || $by_name->{$key};
        unless ($fn) {
            unless ($ignore_unknown) {
                ProtocolBuffers::PP::Error->throw('json', "Unknown field in JSON: $key");
            }
            next;
        }

        my $fd = $fields->{$fn};
        my $value = $data->{$key};

        # Handle null
        if (!defined $value || (ref $value eq 'JSON::PP::Boolean' && !$value && !ref $value)) {
            # JSON null — for most fields, skip (means default/absent)
            # But for wrappers and Value, null has meaning
            next unless _is_json_null($value);
            if ($fd->{type} == TYPE_MESSAGE && $fd->{message_descriptor}) {
                my $sub_full = $fd->{message_descriptor}{full_name} || '';
                if ($sub_full eq 'google.protobuf.Value') {
                    # null => NullValue
                    $msg->{$fd->{name}} = { null_value => 0, _oneof_case => { 0 => 1 } };
                    if (defined $fd->{oneof_index}) {
                        $msg->{_oneof_case} ||= {};
                        $msg->{_oneof_case}{$fd->{oneof_index}} = $fn;
                    }
                    next;
                }
            }
            # For oneof: null clears, for others: skip
            next;
        }

        # Map fields
        if ($fd->{map_entry}) {
            unless (ref $value eq 'HASH') {
                ProtocolBuffers::PP::Error->throw('json', "Expected JSON object for map field $key");
            }
            my $me = $fd->{map_entry};
            # For message-valued maps, use value_message_descriptor
            my $val_fd = $fd;
            if ($me->{value_type} == TYPE_MESSAGE && $me->{value_message_descriptor}) {
                $val_fd = { %$fd, message_descriptor => $me->{value_message_descriptor} };
            }
            if ($me->{value_type} == TYPE_ENUM && $me->{value_enum_class}) {
                $val_fd = { %$fd, enum_class => $me->{value_enum_class} };
            }
            for my $mk (keys %$value) {
                my $parsed_key = _parse_map_key($mk, $me->{key_type});
                my $parsed_val = _parse_scalar_or_message($value->{$mk}, $me->{value_type}, $val_fd, %opts);
                $msg->{$fd->{name}}{$parsed_key} = $parsed_val;
            }
            next;
        }

        # Repeated fields
        if ($fd->{label} == LABEL_REPEATED) {
            unless (ref $value eq 'ARRAY') {
                ProtocolBuffers::PP::Error->throw('json', "Expected JSON array for repeated field $key");
            }
            $msg->{$fd->{name}} = [map { _parse_scalar_or_message($_, $fd->{type}, $fd, %opts) } @$value];
            next;
        }

        # Oneof tracking
        if (defined $fd->{oneof_index}) {
            # Reject duplicate oneof fields
            if ($msg->{_oneof_case} && defined $msg->{_oneof_case}{$fd->{oneof_index}}) {
                ProtocolBuffers::PP::Error->throw('json', "Duplicate oneof field in JSON");
            }
            # Clear other oneof members
            my $oneof = $descriptor->{oneofs}[$fd->{oneof_index}];
            if ($oneof) {
                for my $ofn (@{$oneof->{fields}}) {
                    next if $ofn == $fn;
                    my $ofd = $fields->{$ofn};
                    $msg->{$ofd->{name}} = undef if $ofd;
                }
            }
            $msg->{_oneof_case} ||= {};
            $msg->{_oneof_case}{$fd->{oneof_index}} = $fn;
        }

        $msg->{$fd->{name}} = _parse_scalar_or_message($value, $fd->{type}, $fd, %opts);
    }

    return $msg;
}

sub _parse_scalar_or_message {
    my ($value, $type, $fd, %opts) = @_;

    if ($type == TYPE_MESSAGE) {
        my $sub_desc = $fd->{message_descriptor};
        if (!$sub_desc) {
            # Try resolving via message_class
            if ($fd->{message_class}) {
                $sub_desc = $fd->{message_class}->__DESCRIPTOR__;
            }
        }
        return undef unless defined $value;

        # For non-WKT messages, value must be a JSON object
        if ($sub_desc) {
            my $sub_full = $sub_desc->{full_name} || '';
            if (my $parser = $WKT_PARSERS{$sub_full}) {
                return $parser->($value, $sub_desc, %opts);
            }
            unless (ref $value eq 'HASH') {
                ProtocolBuffers::PP::Error->throw('json', "Expected JSON object for message field");
            }
            return _parse_hash($value, $sub_desc, %opts);
        }
        return $value;
    }

    return _parse_scalar($value, $type, $fd);
}

sub _parse_scalar {
    my ($value, $type, $fd) = @_;

    if ($type == TYPE_BOOL) {
        if (ref $value eq 'JSON::PP::Boolean') {
            return $value ? 1 : 0;
        }
        if (!ref $value) {
            return 1 if $value eq 'true';
            return 0 if $value eq 'false';
        }
        ProtocolBuffers::PP::Error->throw('json', "Invalid bool value");
    }

    if ($type == TYPE_STRING) {
        # Reject non-string JSON types (booleans, arrays, hashes, numbers)
        if (ref $value) {
            ProtocolBuffers::PP::Error->throw('json', "Expected string, got " . ref($value));
        }
        if (_is_json_number($value)) {
            ProtocolBuffers::PP::Error->throw('json', "Expected string, got number");
        }
        return "$value";
    }

    if ($type == TYPE_BYTES) {
        ProtocolBuffers::PP::Error->throw('json', "Expected string for bytes") if ref $value;
        # Accept standard and URL-safe base64
        my $b64 = $value;
        $b64 =~ tr{-_}{+/};
        # Add padding if needed
        while (length($b64) % 4) {
            $b64 .= '=';
        }
        return MIME::Base64::decode_base64($b64);
    }

    if ($type == TYPE_DOUBLE || $type == TYPE_FLOAT) {
        return _parse_float_value($value, $type);
    }

    if ($type == TYPE_ENUM) {
        if (ref $value eq 'JSON::PP::Boolean') {
            ProtocolBuffers::PP::Error->throw('json', "Expected enum, got boolean");
        }
        if (!ref $value && $value =~ /^-?\d+$/) {
            return int($value);
        }
        # Look up name
        if ($fd && $fd->{enum_class}) {
            my $num = $fd->{enum_class}->value_for($value);
            if (defined $num) {
                return $num;
            }
        }
        ProtocolBuffers::PP::Error->throw('json', "Unknown enum value: $value");
    }

    # All integer types
    my $num = _parse_json_integer($value);

    # Range validation
    if ($type == TYPE_INT32 || $type == TYPE_SINT32 || $type == TYPE_SFIXED32) {
        if ($num < -2147483648 || $num > 2147483647) {
            ProtocolBuffers::PP::Error->throw('json', "Integer out of range for int32: $num");
        }
    } elsif ($type == TYPE_UINT32 || $type == TYPE_FIXED32) {
        if ($num < 0 || $num > 4294967295) {
            ProtocolBuffers::PP::Error->throw('json', "Integer out of range for uint32: $num");
        }
    } elsif ($type == TYPE_INT64 || $type == TYPE_SINT64 || $type == TYPE_SFIXED64) {
        # Perl native int64: check against string representation for overflow
        if (!ref $value && "$value" =~ /^-?\d+$/) {
            # Check string length for obvious overflow
            my $sval = "$value";
            $sval =~ s/^-//;
            if (length($sval) > 19 || ($value =~ /^-/ && length($sval) == 19 && $sval gt '9223372036854775808')
                || ($value !~ /^-/ && length($sval) == 19 && $sval gt '9223372036854775807')) {
                ProtocolBuffers::PP::Error->throw('json', "Integer out of range for int64: $value");
            }
        }
    } elsif ($type == TYPE_UINT64 || $type == TYPE_FIXED64) {
        if ($num < 0) {
            ProtocolBuffers::PP::Error->throw('json', "Integer out of range for uint64: $num");
        }
        # Check for values > 2^64-1
        if (!ref $value && "$value" =~ /^\d+$/) {
            my $sval = "$value";
            if (length($sval) > 20 || (length($sval) == 20 && $sval gt '18446744073709551615')) {
                ProtocolBuffers::PP::Error->throw('json', "Integer out of range for uint64: $value");
            }
        }
    }

    return $num;
}

sub _parse_float_value {
    my ($value, $type) = @_;

    if (ref $value eq 'JSON::PP::Boolean') {
        ProtocolBuffers::PP::Error->throw('json', "Expected number, got boolean");
    }
    if (!ref $value) {
        return _nan() if $value eq 'NaN';
        return 9**9**9 if $value eq 'Infinity';
        return -(9**9**9) if $value eq '-Infinity';
        unless (_is_valid_number($value)) {
            ProtocolBuffers::PP::Error->throw('json', "Invalid number: $value");
        }
    }
    my $num = $value + 0;

    # Float range check: +-3.4028235e+38 (plus inf/nan are OK)
    if (defined $type && $type == TYPE_FLOAT) {
        if ($num == $num && $num != 9**9**9 && $num != -(9**9**9)) {
            if ($num > 3.4028235e+38 || $num < -3.4028235e+38) {
                ProtocolBuffers::PP::Error->throw('json', "Float out of range: $value");
            }
        }
    }

    return $num;
}

sub _parse_json_integer {
    my ($value) = @_;

    if (ref $value eq 'JSON::PP::Boolean') {
        ProtocolBuffers::PP::Error->throw('json', "Expected integer, got boolean");
    }

    # Handle string values (JSON strings or Perl stringified numbers)
    if (!ref $value) {
        # Reject leading/trailing whitespace in string values
        if ($value =~ /^\s/ || $value =~ /\s$/) {
            ProtocolBuffers::PP::Error->throw('json', "Invalid integer value (whitespace): $value");
        }

        # Plain integer
        if ($value =~ /^-?\d+$/) {
            return int($value);
        }

        # Float notation that represents a whole number (e.g., "1.0", "1e5")
        if (_is_valid_number($value)) {
            my $num = $value + 0;
            if ($num == int($num)) {
                return int($num);
            }
            ProtocolBuffers::PP::Error->throw('json', "Non-integer value: $value");
        }

        ProtocolBuffers::PP::Error->throw('json', "Invalid integer value: $value");
    }

    # Ref value (shouldn't happen from JSON::PP for normal numbers)
    my $num = $value + 0;
    if ($num != int($num)) {
        ProtocolBuffers::PP::Error->throw('json', "Non-integer value");
    }
    return int($num);
}

sub _parse_map_key {
    my ($key, $key_type) = @_;
    if ($key_type == TYPE_BOOL) {
        return 1 if $key eq 'true';
        return 0 if $key eq 'false';
        ProtocolBuffers::PP::Error->throw('json', "Invalid bool map key: $key");
    }
    # Signed integer key types
    if ($key_type == TYPE_INT32 || $key_type == TYPE_INT64 ||
        $key_type == TYPE_SINT32 || $key_type == TYPE_SINT64 ||
        $key_type == TYPE_SFIXED32 || $key_type == TYPE_SFIXED64) {
        unless ($key =~ /^-?\d+$/) {
            ProtocolBuffers::PP::Error->throw('json', "Invalid integer map key: $key");
        }
        my $num = int($key);
        if ($key_type == TYPE_INT32 || $key_type == TYPE_SINT32 || $key_type == TYPE_SFIXED32) {
            if ($num < -2147483648 || $num > 2147483647) {
                ProtocolBuffers::PP::Error->throw('json', "Map key out of range for int32: $key");
            }
        }
        return $num;
    }
    # Unsigned integer key types
    if ($key_type == TYPE_UINT32 || $key_type == TYPE_UINT64 ||
        $key_type == TYPE_FIXED32 || $key_type == TYPE_FIXED64) {
        unless ($key =~ /^\d+$/) {
            ProtocolBuffers::PP::Error->throw('json', "Invalid unsigned integer map key: $key");
        }
        my $num = int($key);
        if ($key_type == TYPE_UINT32 || $key_type == TYPE_FIXED32) {
            if ($num > 4294967295) {
                ProtocolBuffers::PP::Error->throw('json', "Map key out of range for uint32: $key");
            }
        }
        return $num;
    }
    return $key;
}

sub _is_json_null {
    my ($val) = @_;
    return !defined $val;
}

sub _is_valid_number {
    my ($val) = @_;
    return 0 unless defined $val;
    return $val =~ /^-?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?$/;
}

sub _nan {
    return unpack("d<", pack("Q<", 0x7FF8000000000000));
}

# WKT parsers
sub _parse_timestamp {
    my ($data, $descriptor, %opts) = @_;
    return string_to_timestamp($data);
}

sub _parse_duration {
    my ($data, $descriptor, %opts) = @_;
    return string_to_duration($data);
}

sub _parse_field_mask {
    my ($data, $descriptor, %opts) = @_;
    return string_to_field_mask($data);
}

sub _parse_any {
    my ($data, $descriptor, %opts) = @_;
    my $type_registry = $opts{type_registry} || {};

    unless (ref $data eq 'HASH') {
        ProtocolBuffers::PP::Error->throw('json', 'Expected JSON object for Any');
    }

    # Any without @type key is valid — represents an empty Any
    unless (exists $data->{'@type'}) {
        return { type_url => '', value => '' };
    }

    # @type present but empty is invalid
    unless ($data->{'@type'}) {
        ProtocolBuffers::PP::Error->throw('json', 'Any @type field is empty');
    }

    my $type_url = $data->{'@type'};
    my $full_name = $type_url;
    $full_name =~ s{^.*/}{};

    my $reg_entry = $type_registry->{$full_name};
    unless ($reg_entry) {
        ProtocolBuffers::PP::Error->throw('json', "Unknown type in Any: $type_url");
    }

    my $inner_desc = $reg_entry->{descriptor};
    my $inner_full = $inner_desc->{full_name} || '';
    my $inner_msg;

    if ($WKT_PARSERS{$inner_full} && exists $data->{value}) {
        $inner_msg = $WKT_PARSERS{$inner_full}->($data->{value}, $inner_desc, %opts);
    } else {
        my %remaining = %$data;
        delete $remaining{'@type'};
        $inner_msg = _parse_hash(\%remaining, $inner_desc, %opts);
    }

    my $encoded = ProtocolBuffers::PP::Encode::encode_message($inner_msg || {}, $inner_desc);
    return {
        type_url => $type_url,
        value    => $encoded,
    };
}

sub _parse_struct {
    my ($data, $descriptor, %opts) = @_;
    unless (ref $data eq 'HASH') {
        ProtocolBuffers::PP::Error->throw('json', 'Expected JSON object for Struct');
    }
    my %fields;
    for my $key (keys %$data) {
        $fields{$key} = _json_to_value($data->{$key}, %opts);
    }
    return { fields => \%fields };
}

sub _parse_value {
    my ($data, $descriptor, %opts) = @_;
    return _json_to_value($data, %opts);
}

sub _json_to_value {
    my ($data, %opts) = @_;
    if (!defined $data) {
        return { null_value => 0, _oneof_case => { 0 => 1 } };
    }
    if (ref $data eq 'JSON::PP::Boolean') {
        return { bool_value => ($data ? 1 : 0), _oneof_case => { 0 => 4 } };
    }
    if (ref $data eq 'HASH') {
        my %fields;
        for my $key (keys %$data) {
            $fields{$key} = _json_to_value($data->{$key}, %opts);
        }
        return { struct_value => { fields => \%fields }, _oneof_case => { 0 => 5 } };
    }
    if (ref $data eq 'ARRAY') {
        my @values = map { _json_to_value($_, %opts) } @$data;
        return { list_value => { values => \@values }, _oneof_case => { 0 => 6 } };
    }
    # Distinguish JSON numbers from JSON strings using Perl's internal SV flags.
    # JSON::PP sets IOK/NOK for JSON numbers and POK for JSON strings.
    if (_is_json_number($data)) {
        return { number_value => $data + 0, _oneof_case => { 0 => 2 } };
    }
    # String
    return { string_value => "$data", _oneof_case => { 0 => 3 } };
}

sub _is_json_number {
    return 0 if !defined $_[0] || ref $_[0];
    my $flags = B::svref_2object(\$_[0])->FLAGS;
    return ($flags & (B::SVp_IOK() | B::SVp_NOK())) ? 1 : 0;
}

sub _parse_list_value {
    my ($data, $descriptor, %opts) = @_;
    unless (ref $data eq 'ARRAY') {
        ProtocolBuffers::PP::Error->throw('json', 'Expected JSON array for ListValue');
    }
    my @values = map { _json_to_value($_, %opts) } @$data;
    return { values => \@values };
}

sub _parse_wrapper {
    my ($data, $descriptor, %opts) = @_;
    return undef unless defined $data;
    my $fd = $descriptor->{fields}{1};
    return { value => _parse_scalar($data, $fd->{type}, $fd) };
}

1;

__END__

=head1 NAME

ProtocolBuffers::PP::JSON::Parse - ProtoJSON-to-message deserializer

=head1 SYNOPSIS

    use ProtocolBuffers::PP::JSON::Parse qw(parse_message);

    my $msg = parse_message($json_string, $descriptor, %opts);

=head1 DESCRIPTION

Parses a ProtoJSON string into a protobuf message hash. Implements the full
Proto3 JSON mapping including:

=over 4

=item *

Field lookup by both JSON name (camelCase) and proto name (snake_case)

=item *

64-bit integers accepted as JSON strings or numbers

=item *

Bytes fields parsed from base64 (standard and URL-safe)

=item *

Enum values parsed by name or numeric value

=item *

Integer range validation for all integer types

=item *

Full Well-Known Type (WKT) support: Timestamp, Duration, FieldMask,
Any, Struct, Value, ListValue, and all wrapper types

=back

Uses C<B::svref_2object> to inspect Perl SV flags for distinguishing JSON
numbers from JSON strings, which is essential for correct
C<google.protobuf.Value> mapping.

=head1 FUNCTIONS

=head2 parse_message($json, $descriptor, %opts)

Parses a JSON string (or pre-decoded Perl data structure) into a message
hash. Options:

=over 4

=item ignore_unknown_fields

If true, silently skip JSON keys that don't match any field in the
descriptor. Otherwise, throws a L<ProtocolBuffers::PP::Error>.

=item type_registry

Hashref for resolving C<google.protobuf.Any> types.

=back

=head1 SEE ALSO

L<ProtocolBuffers::PP::JSON::Print>, L<ProtocolBuffers::PP::JSON>

=cut
