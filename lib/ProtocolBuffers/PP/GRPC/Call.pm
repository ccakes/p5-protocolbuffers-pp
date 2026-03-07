package ProtocolBuffers::PP::GRPC::Call;
use strict;
use warnings;
use ProtocolBuffers::PP::Encode qw(encode_message);
use ProtocolBuffers::PP::Decode qw(decode_message);

sub new {
    my ($class, %args) = @_;
    return bless {
        transport         => $args{transport},
        stream_id         => $args{stream_id},
        client            => $args{client},
        input_descriptor  => $args{input_descriptor},
        output_descriptor => $args{output_descriptor},
        on_message        => $args{on_message},
        on_close          => $args{on_close},
        on_headers        => $args{on_headers},
        on_trailers       => $args{on_trailers},
        _closed           => 0,
        _buffer           => '',
        _result           => undef,
        _close_sent       => 0,
    }, $class;
}

sub send {
    my ($self, $message) = @_;
    die "Cannot send after close_send()\n" if $self->{_close_sent};
    die "Cannot send on a closed stream\n" if $self->{_closed};
    my $bytes = encode_message($message, $self->{input_descriptor});
    my $frame = pack('CN', 0, length($bytes)) . $bytes;
    $self->{transport}->send_data($self->{stream_id}, $frame);
}

sub close_send {
    my ($self) = @_;
    return if $self->{_close_sent};
    $self->{_close_sent} = 1;
    $self->{transport}->close_send($self->{stream_id});
}

sub cancel {
    my ($self) = @_;
    return if $self->{_closed};
    $self->{transport}->cancel($self->{stream_id});
}

sub wait {
    my ($self, $timeout) = @_;
    $timeout //= 10;
    unless ($self->{_closed}) {
        $self->{transport}->pump_until(sub { $self->{_closed} }, $timeout);
    }
    return $self->{_result};
}

# Called by transport on_data callback
sub _on_data {
    my ($self, $bytes) = @_;
    $self->{_buffer} .= $bytes;

    # Incrementally parse gRPC frames from the buffer
    while (length($self->{_buffer}) >= 5) {
        my ($compressed, $len) = unpack('CN', substr($self->{_buffer}, 0, 5));
        last if length($self->{_buffer}) < 5 + $len;

        my $payload = substr($self->{_buffer}, 5, $len);
        substr($self->{_buffer}, 0, 5 + $len) = '';

        if ($compressed) {
            # We don't support compression; skip this frame
            next;
        }

        my $desc = $self->{output_descriptor};
        my $msg = decode_message($desc, $payload, $desc);
        $self->{on_message}->($msg) if $self->{on_message};
    }
}

# Called by transport on_headers callback
sub _on_headers {
    my ($self, $hdrs, $count) = @_;
    if ($count == 1 && $self->{on_headers}) {
        $self->{on_headers}->($hdrs);
    }
}

# Called by transport on_close callback
sub _on_stream_close {
    my ($self) = @_;
    my $result = $self->{client}->_build_result(
        $self->{transport}, $self->{stream_id},
    );
    $self->{_result} = $result;

    if ($self->{on_trailers} && $result->{trailers}) {
        $self->{on_trailers}->($result->{trailers});
    }

    if ($self->{on_close}) {
        $self->{on_close}->(
            $result->{grpc_status},
            $result->{grpc_message},
            $result,
        );
    }

    $self->{_closed} = 1;
}

1;

__END__

=head1 NAME

ProtocolBuffers::PP::GRPC::Call - Async gRPC streaming call object

=head1 SYNOPSIS

    # Server streaming with callbacks
    my $call = $client->streaming_call($path,
        request            => $message,
        input_descriptor   => $req_desc,
        output_descriptor  => $resp_desc,
        on_message         => sub { my ($msg) = @_; ... },
        on_close           => sub { my ($status, $msg, $result) = @_; ... },
    );
    $call->wait;

    # Client streaming
    my $call = $client->streaming_call($path,
        input_descriptor   => $req_desc,
        output_descriptor  => $resp_desc,
        on_message         => sub { ... },
        on_close           => sub { ... },
    );
    $call->send({ field => 'value' });
    $call->close_send;
    $call->wait;

=head1 DESCRIPTION

Represents an in-flight async streaming gRPC call. Messages are delivered
incrementally via the C<on_message> callback as they arrive from the server.
The C<wait> method blocks until the stream closes.

=head1 METHODS

=head2 send($message_hashref)

Encodes and sends a message on the stream. Dies if called after C<close_send>.

=head2 close_send()

Signals the end of client messages by sending END_STREAM.

=head2 cancel()

Cancels the stream by sending RST_STREAM.

=head2 wait($timeout)

Blocks until the stream is closed or the timeout (default 10 seconds) expires.
Returns the result hash containing C<grpc_status>, C<grpc_message>, C<headers>,
and C<trailers>. Never dies on gRPC errors.

=head1 CALLBACKS

=over 4

=item on_message => sub ($msg) { ... }

Called for each decoded response message as it arrives.

=item on_close => sub ($grpc_status, $grpc_message, $result) { ... }

Called when the stream closes.

=item on_headers => sub ($headers_arrayref) { ... }

Called when the initial response headers arrive.

=item on_trailers => sub ($trailers_arrayref) { ... }

Called when trailers are available (at stream close).

=back

=head1 SEE ALSO

L<ProtocolBuffers::PP::GRPC::Client>, L<ProtocolBuffers::PP::GRPC::Transport>

=cut
