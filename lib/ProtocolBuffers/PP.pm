package ProtocolBuffers::PP;
use strict;
use warnings;

our $VERSION = '0.01';

1;

__END__

=head1 NAME

ProtocolBuffers::PP - Pure-Perl Protocol Buffers implementation

=head1 SYNOPSIS

    use ProtocolBuffers::PP::Encode qw(encode_message);
    use ProtocolBuffers::PP::Decode qw(decode_message);
    use ProtocolBuffers::PP::JSON   qw(encode_json_message decode_json_message);

    # Encode a message to binary wire format
    my $bytes = encode_message($msg, $descriptor);

    # Decode binary wire format to a message hash
    my $msg = decode_message($descriptor, $bytes);

    # Convert to/from canonical ProtoJSON
    my $json = encode_json_message($msg, $descriptor);
    my $msg  = decode_json_message($json, $descriptor);

=head1 DESCRIPTION

ProtocolBuffers::PP is a pure-Perl Protocol Buffers implementation providing
binary wire format encoding/decoding, canonical JSON (ProtoJSON) mapping, a
C<protoc> code generator plugin (C<protoc-gen-perl>), and a gRPC client.

Messages are represented as plain Perl hashes (not blessed objects during
encode/decode). Special keys include C<_oneof_case> for tracking active oneof
fields, and C<_unknown_fields> for preserving unrecognized wire data during
round-tripping.

=head1 SEE ALSO

L<ProtocolBuffers::PP::Encode>, L<ProtocolBuffers::PP::Decode>,
L<ProtocolBuffers::PP::JSON>, L<ProtocolBuffers::PP::Generator>,
L<ProtocolBuffers::PP::GRPC::Client>,
L<ProtocolBuffers::Generated::Message>

=cut
