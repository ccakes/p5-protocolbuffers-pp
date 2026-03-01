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
