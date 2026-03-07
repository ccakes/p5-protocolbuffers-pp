#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use Test::Exception;
use lib 'lib';

use ProtocolBuffers::PP::GRPC::Call;

# Build a minimal descriptor for testing (simulates a simple message with
# a single string field "reply" at field number 1).
my $desc = {
    full_name => 'test.Reply',
    syntax    => 'proto3',
    _class    => 'Test::Reply',
    fields    => {
        1 => {
            name      => 'reply',
            json_name => 'reply',
            number    => 1,
            type      => 9,   # TYPE_STRING
            label     => 1,
            packed    => 0,
            oneof_index => undef,
        },
    },
    fields_by_name      => { reply => 1 },
    fields_by_json_name => { reply => 1 },
    oneofs              => [],
};

# Helper: encode a gRPC frame (1 byte flag + 4 byte BE length + payload)
sub grpc_frame {
    my ($payload) = @_;
    return pack('CN', 0, length($payload)) . $payload;
}

# Helper: encode a simple protobuf string field (field 1, wire type 2)
sub encode_proto_string {
    my ($str) = @_;
    # field 1, wire type 2 (length-delimited) => tag byte = 0x0a
    return "\x0a" . chr(length($str)) . $str;
}

# --- Test: _on_data with a single complete message ---
subtest 'single complete message in one DATA chunk' => sub {
    my @messages;
    my $call = ProtocolBuffers::PP::GRPC::Call->new(
        transport         => undef,
        stream_id         => 1,
        client            => undef,
        input_descriptor  => $desc,
        output_descriptor => $desc,
        on_message        => sub { push @messages, $_[0] },
    );

    my $proto = encode_proto_string("hello");
    $call->_on_data(grpc_frame($proto));

    is(scalar @messages, 1, 'one message decoded');
    is($messages[0]{reply}, 'hello', 'message content correct');
};

# --- Test: partial gRPC frames across DATA callbacks ---
subtest 'partial frames across multiple DATA chunks' => sub {
    my @messages;
    my $call = ProtocolBuffers::PP::GRPC::Call->new(
        transport         => undef,
        stream_id         => 1,
        client            => undef,
        input_descriptor  => $desc,
        output_descriptor => $desc,
        on_message        => sub { push @messages, $_[0] },
    );

    my $proto = encode_proto_string("world");
    my $frame = grpc_frame($proto);

    # Split the frame into 3 parts
    my $part1 = substr($frame, 0, 3);   # partial header
    my $part2 = substr($frame, 3, 4);   # rest of header + some payload
    my $part3 = substr($frame, 7);      # remaining payload

    $call->_on_data($part1);
    is(scalar @messages, 0, 'no message yet after partial header');

    $call->_on_data($part2);
    is(scalar @messages, 0, 'no message yet after partial payload');

    $call->_on_data($part3);
    is(scalar @messages, 1, 'message decoded after all parts received');
    is($messages[0]{reply}, 'world', 'message content correct');
};

# --- Test: multiple complete messages in one DATA callback ---
subtest 'multiple messages in one DATA chunk' => sub {
    my @messages;
    my $call = ProtocolBuffers::PP::GRPC::Call->new(
        transport         => undef,
        stream_id         => 1,
        client            => undef,
        input_descriptor  => $desc,
        output_descriptor => $desc,
        on_message        => sub { push @messages, $_[0] },
    );

    my $frame1 = grpc_frame(encode_proto_string("msg1"));
    my $frame2 = grpc_frame(encode_proto_string("msg2"));
    my $frame3 = grpc_frame(encode_proto_string("msg3"));

    $call->_on_data($frame1 . $frame2 . $frame3);

    is(scalar @messages, 3, 'three messages decoded');
    is($messages[0]{reply}, 'msg1', 'first message correct');
    is($messages[1]{reply}, 'msg2', 'second message correct');
    is($messages[2]{reply}, 'msg3', 'third message correct');
};

# --- Test: zero-length message ---
subtest 'zero-length message' => sub {
    my @messages;
    my $call = ProtocolBuffers::PP::GRPC::Call->new(
        transport         => undef,
        stream_id         => 1,
        client            => undef,
        input_descriptor  => $desc,
        output_descriptor => $desc,
        on_message        => sub { push @messages, $_[0] },
    );

    # gRPC frame with empty payload (0 bytes)
    $call->_on_data(grpc_frame(''));

    is(scalar @messages, 1, 'one message decoded');
    is($messages[0]{reply}, undef, 'empty message has no reply field');
};

# --- Test: send() after close_send() dies ---
subtest 'send after close_send dies' => sub {
    # Mock transport that records calls
    my $mock_transport = bless {
        _data_sent   => [],
        _close_sent  => 0,
        streams      => { 1 => { sent_end_stream => 0 } },
    }, 'MockTransport';

    {
        no strict 'refs';
        *MockTransport::send_data = sub {
            my ($self, $sid, $data) = @_;
            push @{$self->{_data_sent}}, $data;
        };
        *MockTransport::close_send = sub {
            my ($self, $sid) = @_;
            $self->{_close_sent} = 1;
            $self->{streams}{$sid}{sent_end_stream} = 1;
        };
    }

    my $call = ProtocolBuffers::PP::GRPC::Call->new(
        transport         => $mock_transport,
        stream_id         => 1,
        client            => undef,
        input_descriptor  => $desc,
        output_descriptor => $desc,
        on_message        => sub {},
    );

    $call->close_send;
    throws_ok { $call->send({ reply => 'too late' }) }
        qr/Cannot send after close_send/,
        'send after close_send throws';
};

# --- Test: wait() after stream already closed ---
subtest 'wait after already closed returns result' => sub {
    my $call = ProtocolBuffers::PP::GRPC::Call->new(
        transport         => undef,
        stream_id         => 1,
        client            => undef,
        input_descriptor  => $desc,
        output_descriptor => $desc,
        on_message        => sub {},
    );

    # Simulate already closed
    $call->{_closed} = 1;
    $call->{_result} = { grpc_status => 0, grpc_message => undef };

    my $result = $call->wait;
    is($result->{grpc_status}, 0, 'returns stored result');
};

# --- Test: _on_headers callback ---
subtest 'on_headers callback fires on first headers' => sub {
    my @header_calls;
    my $call = ProtocolBuffers::PP::GRPC::Call->new(
        transport         => undef,
        stream_id         => 1,
        client            => undef,
        input_descriptor  => $desc,
        output_descriptor => $desc,
        on_message        => sub {},
        on_headers        => sub { push @header_calls, [@_] },
    );

    $call->_on_headers([':status', '200'], 1);
    is(scalar @header_calls, 1, 'on_headers called for count=1');

    $call->_on_headers(['grpc-status', '0'], 2);
    is(scalar @header_calls, 1, 'on_headers NOT called for count=2 (trailers)');
};

# --- Test: _on_stream_close fires on_close and on_trailers ---
subtest 'on_stream_close fires callbacks' => sub {
    my @close_calls;
    my @trailer_calls;

    # Mock client with _build_result
    my $mock_client = bless {}, 'MockClient';
    {
        no strict 'refs';
        *MockClient::_build_result = sub {
            return {
                grpc_status  => 0,
                grpc_message => undef,
                headers      => [],
                trailers     => [['grpc-status', ['0']]],
            };
        };
    }

    my $call = ProtocolBuffers::PP::GRPC::Call->new(
        transport         => undef,
        stream_id         => 1,
        client            => $mock_client,
        input_descriptor  => $desc,
        output_descriptor => $desc,
        on_message        => sub {},
        on_close          => sub { push @close_calls, [@_] },
        on_trailers       => sub { push @trailer_calls, [@_] },
    );

    $call->_on_stream_close;

    is(scalar @close_calls, 1, 'on_close called');
    is($close_calls[0][0], 0, 'on_close received grpc_status=0');
    is(scalar @trailer_calls, 1, 'on_trailers called');
    ok($call->{_closed}, 'call marked as closed');
    is($call->{_result}{grpc_status}, 0, 'result stored');
};

done_testing;
