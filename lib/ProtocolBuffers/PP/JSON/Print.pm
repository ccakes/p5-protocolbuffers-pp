package ProtocolBuffers::PP::JSON::Print;
use strict;
use warnings;
use JSON::PP;
use MIME::Base64 ();
use ProtocolBuffers::PP::Types qw(
    TYPE_DOUBLE TYPE_FLOAT TYPE_INT64 TYPE_UINT64 TYPE_INT32
    TYPE_FIXED64 TYPE_FIXED32 TYPE_BOOL TYPE_STRING TYPE_GROUP
    TYPE_MESSAGE TYPE_BYTES TYPE_UINT32 TYPE_ENUM TYPE_SFIXED32
    TYPE_SFIXED64 TYPE_SINT32 TYPE_SINT64
    LABEL_REPEATED
);
use ProtocolBuffers::PP::Util qw(default_value_for_type);
use ProtocolBuffers::PP::Timestamp qw(timestamp_to_string);
use ProtocolBuffers::PP::Duration qw(duration_to_string);
use ProtocolBuffers::PP::FieldMask qw(field_mask_to_string);
use ProtocolBuffers::PP::Error;

use Exporter 'import';
our @EXPORT_OK = qw(print_message);

# Lightweight Math::BigFloat subclass that preserves the exact sprintf-formatted
# string through JSON::PP serialisation.  JSON::PP (with allow_bignum) calls
# "$obj" on Math::BigFloat instances, so overriding stringify is sufficient.
{
    package ProtocolBuffers::PP::JSON::FloatLiteral;
    use Math::BigFloat;
    our @ISA = ('Math::BigFloat');

    sub new {
        my ($class, $str) = @_;
        my $self = Math::BigFloat->new($str);
        bless $self, $class;
        $self->{_literal} = $str;
        return $self;
    }

    use overload
        '""' => sub { $_[0]->{_literal} },
        fallback => 1;
}

my $json_pp = JSON::PP->new->canonical(1)->allow_nonref(1)->allow_bignum(1)
    ->utf8(1);

# WKT dispatch table
my %WKT_PRINTERS = (
    'google.protobuf.Timestamp' => \&_print_timestamp,
    'google.protobuf.Duration'  => \&_print_duration,
    'google.protobuf.FieldMask' => \&_print_field_mask,
    'google.protobuf.Any'       => \&_print_any,
    'google.protobuf.Struct'    => \&_print_struct,
    'google.protobuf.Value'     => \&_print_value,
    'google.protobuf.ListValue' => \&_print_list_value,
    'google.protobuf.BoolValue'   => \&_print_wrapper,
    'google.protobuf.Int32Value'  => \&_print_wrapper,
    'google.protobuf.Int64Value'  => \&_print_wrapper,
    'google.protobuf.UInt32Value' => \&_print_wrapper,
    'google.protobuf.UInt64Value' => \&_print_wrapper,
    'google.protobuf.FloatValue'  => \&_print_wrapper,
    'google.protobuf.DoubleValue' => \&_print_wrapper,
    'google.protobuf.StringValue' => \&_print_wrapper,
    'google.protobuf.BytesValue'  => \&_print_wrapper,
);

sub print_message {
    my ($msg, $descriptor, %opts) = @_;

    my $full_name = $descriptor->{full_name} || '';

    # Check WKT dispatch
    if (my $printer = $WKT_PRINTERS{$full_name}) {
        my $data = $printer->($msg, $descriptor, %opts);
        return $json_pp->encode($data);
    }

    my $data = _message_to_hash($msg, $descriptor, %opts);
    return $json_pp->encode($data);
}

sub _message_to_hash {
    my ($msg, $descriptor, %opts) = @_;
    my $fields = $descriptor->{fields};
    my %result;
    my $emit_defaults = $opts{emit_defaults} || 0;
    my $syntax = $descriptor->{syntax} || 'proto3';

    for my $fn (sort { $a <=> $b } keys %$fields) {
        my $fd = $fields->{$fn};
        my $name = $fd->{name};
        my $json_name = $fd->{json_name} || $name;
        my $value = $msg->{$name};

        # Map fields
        if ($fd->{map_entry}) {
            next unless defined $value && ref $value eq 'HASH' && %$value;
            my $me = $fd->{map_entry};
            my %map_result;
            # For message-valued maps, use the value_message_descriptor
            my $val_fd = $fd;
            if ($me->{value_type} == TYPE_MESSAGE && $me->{value_message_descriptor}) {
                $val_fd = { %$fd, message_descriptor => $me->{value_message_descriptor} };
            }
            # For enum-valued maps, use the value_enum_class
            if ($me->{value_type} == TYPE_ENUM && $me->{value_enum_class}) {
                $val_fd = { %$fd, enum_class => $me->{value_enum_class} };
            }
            for my $k (sort keys %$value) {
                my $map_key = _format_map_key($k, $me->{key_type});
                $map_result{$map_key} = _format_value($value->{$k}, $me->{value_type}, $val_fd, %opts);
            }
            $result{$json_name} = \%map_result;
            next;
        }

        # Repeated fields
        if ($fd->{label} == LABEL_REPEATED) {
            next unless defined $value && ref $value eq 'ARRAY' && @$value;
            $result{$json_name} = [map { _format_value($_, $fd->{type}, $fd, %opts) } @$value];
            next;
        }

        # Oneof
        if (defined $fd->{oneof_index}) {
            my $active = $msg->{_oneof_case} && $msg->{_oneof_case}{$fd->{oneof_index}};
            if (defined $active && $active == $fn) {
                $result{$json_name} = _format_value($value, $fd->{type}, $fd, %opts);
            }
            next;
        }

        # Singular field — proto3 default omission
        if ($syntax eq 'proto3' && !$fd->{proto3_optional} && !$emit_defaults) {
            next unless defined $value && !_is_default($value, $fd->{type});
        }

        if (defined $value) {
            $result{$json_name} = _format_value($value, $fd->{type}, $fd, %opts);
        }
    }

    return \%result;
}

sub _format_value {
    my ($value, $type, $fd, %opts) = @_;

    if ($type == TYPE_MESSAGE) {
        return undef unless defined $value;
        my $sub_desc = $fd->{message_descriptor};
        if ($sub_desc) {
            my $full_name = $sub_desc->{full_name} || '';
            if (my $printer = $WKT_PRINTERS{$full_name}) {
                return $printer->($value, $sub_desc, %opts);
            }
            return _message_to_hash($value, $sub_desc, %opts);
        }
        return $value;
    }

    return _format_scalar($value, $type, $fd);
}

sub _format_scalar {
    my ($value, $type, $fd) = @_;

    if ($type == TYPE_BOOL) {
        return $value ? JSON::PP::true : JSON::PP::false;
    }

    if ($type == TYPE_STRING) {
        return $value;
    }

    if ($type == TYPE_BYTES) {
        return MIME::Base64::encode_base64(defined $value ? $value : '', '');
    }

    if ($type == TYPE_DOUBLE || $type == TYPE_FLOAT) {
        return _format_float($value, $type);
    }

    # 64-bit integers as strings
    if ($type == TYPE_INT64 || $type == TYPE_SINT64 || $type == TYPE_SFIXED64) {
        return "" . (defined $value ? $value : 0);
    }
    if ($type == TYPE_UINT64 || $type == TYPE_FIXED64) {
        return "" . (defined $value ? $value : 0);
    }

    if ($type == TYPE_ENUM) {
        # Try to get enum name
        if ($fd && $fd->{enum_class}) {
            my $name = $fd->{enum_class}->name_for($value);
            return $name if defined $name;
        }
        return (defined $value ? $value : 0) + 0;
    }

    # All other integer types as numbers
    return (defined $value ? $value : 0) + 0;
}

sub _format_float {
    my ($value, $type) = @_;
    $value = 0.0 unless defined $value;

    # Handle special values — the JSON spec for protobuf requires these as strings
    if ($value != $value) {
        return "NaN";
    }
    if ($value == 9**9**9) {
        return "Infinity";
    }
    if ($value == -(9**9**9)) {
        return "-Infinity";
    }

    # IEEE 754 requires 17 significant digits for double and 9 for float
    # to guarantee round-trip fidelity.  Perl's default NV stringification
    # uses %.15g which can lose the last few digits of a double.
    my $precision = (defined $type && $type == TYPE_FLOAT) ? 9 : 17;
    my $formatted = sprintf("%.${precision}g", $value);

    # Return a FloatLiteral so JSON::PP (with allow_bignum) emits the
    # exact formatted string as a bare JSON number.
    return ProtocolBuffers::PP::JSON::FloatLiteral->new($formatted);
}

sub _format_map_key {
    my ($key, $key_type) = @_;
    if ($key_type == TYPE_BOOL) {
        return $key ? 'true' : 'false';
    }
    return "$key";
}

sub _is_default {
    my ($value, $type) = @_;
    if ($type == TYPE_STRING || $type == TYPE_BYTES) {
        return $value eq '';
    }
    if ($type == TYPE_BOOL) {
        return !$value;
    }
    if ($type == TYPE_MESSAGE) {
        return !defined $value;
    }
    if ($type == TYPE_DOUBLE || $type == TYPE_FLOAT) {
        return $value == 0 && sprintf("%g", $value) ne '-0';
    }
    return $value == 0;
}

# WKT printers
sub _print_timestamp {
    my ($msg, $descriptor, %opts) = @_;
    return timestamp_to_string($msg);
}

sub _print_duration {
    my ($msg, $descriptor, %opts) = @_;
    return duration_to_string($msg);
}

sub _print_field_mask {
    my ($msg, $descriptor, %opts) = @_;
    return field_mask_to_string($msg);
}

sub _print_any {
    my ($msg, $descriptor, %opts) = @_;
    my $type_url = $msg->{type_url} || '';
    my $type_registry = $opts{type_registry} || {};

    # Empty Any (no type_url) serializes as empty JSON object
    return {} if $type_url eq '';

    my $full_name = $type_url;
    $full_name =~ s{^.*/}{};

    my $reg_entry = $type_registry->{$full_name};
    unless ($reg_entry) {
        ProtocolBuffers::PP::Error->throw('json', "Unknown type in Any: $type_url");
    }

    my $inner_desc = $reg_entry->{descriptor};
    my $inner_msg = ProtocolBuffers::PP::Decode::decode_message($inner_desc, $msg->{value} || '', $inner_desc);

    my $inner_full = $inner_desc->{full_name} || '';
    if (my $printer = $WKT_PRINTERS{$inner_full}) {
        return { '@type' => $type_url, value => $printer->($inner_msg, $inner_desc, %opts) };
    }

    my $hash = _message_to_hash($inner_msg, $inner_desc, %opts);
    return { '@type' => $type_url, %$hash };
}

sub _print_struct {
    my ($msg, $descriptor, %opts) = @_;
    my $fields = $msg->{fields} || {};
    my %result;
    for my $key (sort keys %$fields) {
        my $val = $fields->{$key};
        $result{$key} = _print_value_inner($val, %opts);
    }
    return \%result;
}

sub _print_value {
    my ($msg, $descriptor, %opts) = @_;
    return _print_value_inner($msg, %opts);
}

sub _print_value_inner {
    my ($msg, %opts) = @_;
    return JSON::PP::null unless defined $msg;

    my $oneof = $msg->{_oneof_case};
    if ($oneof && defined $oneof->{0}) {
        my $case = $oneof->{0};
        if ($case == 1) { # null_value
            return JSON::PP::null;
        } elsif ($case == 2) { # number_value
            return $msg->{number_value} + 0;
        } elsif ($case == 3) { # string_value
            return $msg->{string_value};
        } elsif ($case == 4) { # bool_value
            return $msg->{bool_value} ? JSON::PP::true : JSON::PP::false;
        } elsif ($case == 5) { # struct_value
            return _print_struct($msg->{struct_value}, undef, %opts);
        } elsif ($case == 6) { # list_value
            return _print_list_value($msg->{list_value}, undef, %opts);
        }
    }

    # Detect by which field is set
    if (defined $msg->{null_value}) { return JSON::PP::null }
    if (defined $msg->{number_value}) { return $msg->{number_value} + 0 }
    if (defined $msg->{string_value}) { return $msg->{string_value} }
    if (defined $msg->{bool_value}) { return $msg->{bool_value} ? JSON::PP::true : JSON::PP::false }
    if (defined $msg->{struct_value}) { return _print_struct($msg->{struct_value}, undef, %opts) }
    if (defined $msg->{list_value}) { return _print_list_value($msg->{list_value}, undef, %opts) }

    return JSON::PP::null;
}

sub _print_list_value {
    my ($msg, $descriptor, %opts) = @_;
    my $values = $msg->{values} || [];
    return [map { _print_value_inner($_, %opts) } @$values];
}

sub _print_wrapper {
    my ($msg, $descriptor, %opts) = @_;
    # Wrapper types: the JSON representation is just the unwrapped value
    my $value = $msg->{value};
    return undef unless defined $msg;  # null = absent

    my $full_name = $descriptor->{full_name} || '';
    my $fields = $descriptor->{fields};
    # Value field is field 1
    my $fd = $fields->{1};
    return _format_scalar($value, $fd->{type}, $fd) if $fd;
    return $value;
}

1;
