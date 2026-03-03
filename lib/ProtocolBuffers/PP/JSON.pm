package ProtocolBuffers::PP::JSON;
use strict;
use warnings;
use ProtocolBuffers::PP::JSON::Print;
use ProtocolBuffers::PP::JSON::Parse;

use Exporter 'import';
our @EXPORT_OK = qw(encode_json_message decode_json_message);

sub encode_json_message {
    my ($msg, $descriptor, %opts) = @_;
    return ProtocolBuffers::PP::JSON::Print::print_message($msg, $descriptor, %opts);
}

sub decode_json_message {
    my ($json, $descriptor, %opts) = @_;
    return ProtocolBuffers::PP::JSON::Parse::parse_message($json, $descriptor, %opts);
}

1;

__END__

=head1 NAME

ProtocolBuffers::PP::JSON - Convenience interface for ProtoJSON encoding/decoding

=head1 SYNOPSIS

    use ProtocolBuffers::PP::JSON qw(encode_json_message decode_json_message);

    my $json = encode_json_message($msg, $descriptor, %opts);
    my $msg  = decode_json_message($json, $descriptor, %opts);

=head1 DESCRIPTION

Thin wrapper around L<ProtocolBuffers::PP::JSON::Print> and
L<ProtocolBuffers::PP::JSON::Parse>, providing a single import point for
ProtoJSON conversion.

=head1 FUNCTIONS

=head2 encode_json_message($msg, $descriptor, %opts)

Converts a message hash to a canonical ProtoJSON string. Delegates to
L<ProtocolBuffers::PP::JSON::Print/print_message>.

Options: C<emit_defaults>, C<type_registry>.

=head2 decode_json_message($json, $descriptor, %opts)

Parses a ProtoJSON string into a message hash. Delegates to
L<ProtocolBuffers::PP::JSON::Parse/parse_message>.

Options: C<ignore_unknown_fields>, C<type_registry>.

=head1 SEE ALSO

L<ProtocolBuffers::PP::JSON::Print>, L<ProtocolBuffers::PP::JSON::Parse>

=cut
