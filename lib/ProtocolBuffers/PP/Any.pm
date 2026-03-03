package ProtocolBuffers::PP::Any;
use strict;
use warnings;
use ProtocolBuffers::PP::Error;

use Exporter 'import';
our @EXPORT_OK = qw(any_to_json json_to_any);

# WKT full names that get {"@type": ..., "value": ...} format
my %WKT_VALUE_TYPES = map { $_ => 1 } qw(
    google.protobuf.Timestamp
    google.protobuf.Duration
    google.protobuf.FieldMask
    google.protobuf.Struct
    google.protobuf.Value
    google.protobuf.ListValue
    google.protobuf.BoolValue
    google.protobuf.Int32Value
    google.protobuf.Int64Value
    google.protobuf.UInt32Value
    google.protobuf.UInt64Value
    google.protobuf.FloatValue
    google.protobuf.DoubleValue
    google.protobuf.StringValue
    google.protobuf.BytesValue
);

sub any_to_json {
    my ($msg, %opts) = @_;
    my $type_url = $msg->{type_url} || '';
    my $type_registry = $opts{type_registry} || {};
    my $json_printer = $opts{json_printer};

    # Extract full name from type_url
    my $full_name = $type_url;
    $full_name =~ s{^.*/}{};  # strip everything before last /

    my $reg_entry = $type_registry->{$full_name};
    unless ($reg_entry) {
        ProtocolBuffers::PP::Error->throw('json', "Unknown type in Any: $type_url");
    }

    # Decode the value bytes
    my $descriptor = $reg_entry->{descriptor};
    my $inner_msg = ProtocolBuffers::PP::Decode::decode_message($descriptor, $msg->{value} || '', $descriptor);

    if ($WKT_VALUE_TYPES{$full_name} && $json_printer) {
        # WKT: use {"@type": ..., "value": ...}
        my $value_json = $json_printer->($inner_msg, $descriptor);
        return { '@type' => $type_url, value => $value_json };
    }

    # Regular message: merge @type into the JSON object
    my $json_hash = $json_printer ? $json_printer->($inner_msg, $descriptor) : {};
    if (ref $json_hash eq 'HASH') {
        return { '@type' => $type_url, %$json_hash };
    }
    return { '@type' => $type_url, value => $json_hash };
}

sub json_to_any {
    my ($json_data, %opts) = @_;
    my $type_registry = $opts{type_registry} || {};
    my $json_parser = $opts{json_parser};

    my $type_url = $json_data->{'@type'};
    unless ($type_url) {
        ProtocolBuffers::PP::Error->throw('json', 'Any missing @type field');
    }

    my $full_name = $type_url;
    $full_name =~ s{^.*/}{};

    my $reg_entry = $type_registry->{$full_name};
    unless ($reg_entry) {
        ProtocolBuffers::PP::Error->throw('json', "Unknown type in Any: $type_url");
    }

    my $descriptor = $reg_entry->{descriptor};
    my $inner_msg;

    if ($WKT_VALUE_TYPES{$full_name} && exists $json_data->{value}) {
        $inner_msg = $json_parser->($json_data->{value}, $descriptor) if $json_parser;
    } else {
        # Regular message: remove @type, parse remaining
        my %remaining = %$json_data;
        delete $remaining{'@type'};
        $inner_msg = $json_parser->(\%remaining, $descriptor) if $json_parser;
    }

    my $encoded = ProtocolBuffers::PP::Encode::encode_message($inner_msg || {}, $descriptor);

    return {
        type_url => $type_url,
        value    => $encoded,
    };
}

1;

__END__

=head1 NAME

ProtocolBuffers::PP::Any - Helper functions for google.protobuf.Any JSON conversion

=head1 SYNOPSIS

    use ProtocolBuffers::PP::Any qw(any_to_json json_to_any);

    my $json_hash = any_to_json($any_msg,
        type_registry => \%registry,
        json_printer  => \&printer,
    );

    my $any_msg = json_to_any($json_hash,
        type_registry => \%registry,
        json_parser   => \&parser,
    );

=head1 DESCRIPTION

Provides conversion helpers for C<google.protobuf.Any> messages. An Any
wraps an arbitrary message as C<{type_url, value}> where C<value> is the
binary-encoded inner message.

Well-Known Types use C<{"@type": ..., "value": ...}> JSON format, while
regular messages merge their fields alongside C<@type>.

=head1 FUNCTIONS

=head2 any_to_json($msg, %opts)

Converts an Any message hash to a JSON-ready Perl hash. Requires
C<type_registry> and C<json_printer> options.

=head2 json_to_any($json_data, %opts)

Converts a JSON hash (with C<@type> key) to an Any message hash. Requires
C<type_registry> and C<json_parser> options.

=head1 SEE ALSO

L<ProtocolBuffers::PP::JSON::Print>, L<ProtocolBuffers::PP::JSON::Parse>

=cut
