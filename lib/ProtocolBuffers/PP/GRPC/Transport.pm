package ProtocolBuffers::PP::GRPC::Transport;
use strict;
use warnings;
use Mojo::IOLoop;
use Protocol::HTTP2::Connection;
use Protocol::HTTP2::Constants qw(
    :endpoints :frame_types :flags :states :errors :settings PREFACE
);

# Tied hash where EXISTS always returns true.
# Used to tell Protocol::HTTP2 that any trailer header name is valid
# (gRPC doesn't send a Trailer: header, but does send trailing HEADERS).
{
    package ProtocolBuffers::PP::GRPC::Transport::PermissiveHash;
    sub TIEHASH  { bless {}, shift }
    sub EXISTS   { 1 }
    sub FETCH    { $_[0]->{$_[1]} }
    sub STORE    { $_[0]->{$_[1]} = $_[2] }
    sub DELETE   { delete $_[0]->{$_[1]} }
    sub FIRSTKEY { my $a = scalar keys %{$_[0]}; each %{$_[0]} }
    sub NEXTKEY  { each %{$_[0]} }
    sub SCALAR   { 1 }
    sub CLEAR    { %{$_[0]} = () }
}

sub new {
    my ($class, $host, $port) = @_;
    my $self = bless {
        host        => $host,
        port        => $port,
        con         => undef,
        mojo_stream => undef,
        input       => '',
        streams     => {},
        error       => undef,
        connected   => 0,
        _stop_cond  => undef,
    }, $class;

    $self->_connect();
    return $self;
}

sub _connect {
    my ($self) = @_;

    my $con = Protocol::HTTP2::Connection->new(
        CLIENT,
        on_change_state => sub {
            my ($stream_id, $prev, $curr) = @_;
            warn "H2 stream $stream_id state: $prev -> $curr\n" if $ENV{GRPC_DEBUG};
            if ($curr == CLOSED && exists $self->{streams}{$stream_id}) {
                $self->{streams}{$stream_id}{closed} = 1;
            }
        },
        on_error => sub {
            my $error = shift;
            warn "H2 protocol error: $error\n" if $ENV{GRPC_DEBUG};
            $self->{error} = "HTTP/2 protocol error: $error";
        },
    );
    $self->{con} = $con;

    my $done = 0;
    Mojo::IOLoop->client(
        address => $self->{host},
        port    => $self->{port},
        sub {
            my ($loop, $err, $stream) = @_;
            if ($err) {
                $self->{error} = "Connect failed: $err";
                $done = 1;
                Mojo::IOLoop->stop;
                return;
            }
            $self->{mojo_stream} = $stream;
            $self->{connected}   = 1;

            # Send h2c preface (prior knowledge, no Upgrade)
            $con->enqueue_raw($con->preface_encode);
            $con->enqueue(SETTINGS, 0, 0, {});
            $con->preface(1);
            $self->_flush();

            $stream->on(read => sub {
                my ($s, $bytes) = @_;
                $self->_feed($bytes);
                $self->_flush();
                if ($self->{_stop_cond} && $self->{_stop_cond}->()) {
                    Mojo::IOLoop->stop;
                }
            });

            $stream->on(error => sub {
                my ($s, $err) = @_;
                $self->{error} = "Connection error: $err";
                # Only stop if we own the current event loop cycle
                Mojo::IOLoop->stop if $self->{_owns_loop};
            });

            $stream->on(close => sub {
                $self->{connected} = 0;
                # Only stop if we own the current event loop cycle
                Mojo::IOLoop->stop if $self->{_owns_loop};
            });

            $done = 1;
            Mojo::IOLoop->stop;
        }
    );

    Mojo::IOLoop->start unless $done;
    die $self->{error} if $self->{error};
}

sub _feed {
    my ($self, $bytes) = @_;
    if ($ENV{GRPC_DEBUG}) {
        warn "H2 feed: " . length($bytes) . " bytes: " . unpack('H*', substr($bytes, 0, 80)) . "\n";
    }
    $self->{input} .= $bytes;
    my $offset = 0;
    while (my $len = $self->{con}->frame_decode(\$self->{input}, $offset)) {
        $offset += $len;
        # Between frames: apply deferred stream_trailer setup so
        # trailer HEADERS in the same TCP chunk are handled correctly.
        for my $sid (keys %{$self->{streams}}) {
            if (delete $self->{streams}{$sid}{_needs_trailer_setup}) {
                my %permissive;
                tie %permissive, 'ProtocolBuffers::PP::GRPC::Transport::PermissiveHash';
                $self->{con}->stream_trailer($sid, \%permissive);
            }
        }
    }
    substr($self->{input}, 0, $offset) = '' if $offset;

    # Check if connection errored during decode
    if ($self->{con}->shutdown) {
        warn "H2 connection shutdown detected\n" if $ENV{GRPC_DEBUG};
        $self->{error} ||= "Connection shut down by peer";
    }
}

sub _flush {
    my ($self) = @_;
    return unless $self->{mojo_stream};
    while (my $frame = $self->{con}->dequeue) {
        $self->{mojo_stream}->write($frame);
    }
}

sub new_stream {
    my ($self, $headers) = @_;

    my $con       = $self->{con};
    my $stream_id = $con->new_stream;
    die "Cannot create new HTTP/2 stream" unless defined $stream_id;

    $self->{streams}{$stream_id} = {
        response_headers  => undef,
        response_data     => '',
        response_trailers => undef,
        data_chunks       => [],
        closed            => 0,
        headers_count     => 0,
        sent_end_stream   => 0,
    };

    # Track HEADERS frames: first = response headers, second = trailers
    $con->stream_frame_cb($stream_id, HEADERS, sub {
        my $hdrs  = shift;
        my $state = $self->{streams}{$stream_id};
        $state->{headers_count}++;
        warn "H2 stream $stream_id HEADERS #$state->{headers_count}: "
            . join(', ', map { $hdrs->[$_] . '=' . $hdrs->[$_+1] } grep { $_ % 2 == 0 } 0..$#$hdrs) . "\n"
            if $ENV{GRPC_DEBUG};

        if ($state->{headers_count} == 1) {
            $state->{response_headers} = $hdrs;
            if ($state->{sent_end_stream}) {
                # Stream is HALF_CLOSED_LOCAL — safe to set trailer
                # expectation immediately (state machine won't confuse
                # this HEADERS with a trailer).
                my %permissive;
                tie %permissive, 'ProtocolBuffers::PP::GRPC::Transport::PermissiveHash';
                $con->stream_trailer($stream_id, \%permissive);
            } else {
                # Stream is still OPEN (full-duplex bidi) — defer setup
                # until after frame_decode so the state machine doesn't
                # mistake this initial HEADERS for a trailer frame.
                $state->{_needs_trailer_setup} = 1;
            }
        } else {
            $state->{response_trailers} = $hdrs;
        }
    });

    # Accumulate DATA frames
    $con->stream_frame_cb($stream_id, DATA, sub {
        my $data  = shift;
        warn "H2 stream $stream_id DATA: " . length($data) . " bytes\n" if $ENV{GRPC_DEBUG};
        my $state = $self->{streams}{$stream_id};
        $state->{response_data} .= $data;
        push @{$state->{data_chunks}}, $data;
    });

    # Send HEADERS without END_STREAM
    $con->send_headers($stream_id, $headers, 0);
    $self->_flush();

    return $stream_id;
}

sub send_data {
    my ($self, $stream_id, $bytes, $end_stream) = @_;
    $end_stream //= 0;
    $self->{con}->send_data($stream_id, $bytes, $end_stream ? 1 : 0);
    $self->_flush();
}

sub close_send {
    my ($self, $stream_id) = @_;
    $self->{streams}{$stream_id}{sent_end_stream} = 1;
    $self->{con}->send_data($stream_id, '', 1);
    $self->_flush();
}

sub cancel {
    my ($self, $stream_id) = @_;
    $self->{con}->stream_error($stream_id, CANCEL);
    $self->_flush();
    $self->{streams}{$stream_id}{closed} = 1;
    $self->{streams}{$stream_id}{cancelled} = 1;
}

sub pump_until {
    my ($self, $condition, $timeout_secs) = @_;
    $timeout_secs //= 10;
    return if $condition->();

    $self->{_stop_cond} = $condition;
    $self->{_owns_loop} = 1;

    # Periodically check stop condition even without incoming data.
    my $poll_id = Mojo::IOLoop->recurring(0.01 => sub {
        if ($condition->()) {
            Mojo::IOLoop->stop;
        }
    });

    # Safety timeout to prevent hanging forever
    my $timed_out = 0;
    my $timeout_id = Mojo::IOLoop->timer($timeout_secs => sub {
        $timed_out = 1;
        Mojo::IOLoop->stop;
    });

    Mojo::IOLoop->start;

    Mojo::IOLoop->remove($poll_id);
    Mojo::IOLoop->remove($timeout_id);
    $self->{_owns_loop} = 0;
    $self->{_stop_cond} = undef;

    die $self->{error} if $self->{error};
    die "pump_until timed out after ${timeout_secs}s\n" if $timed_out;
}

sub response_headers  { $_[0]->{streams}{$_[1]}{response_headers} }
sub response_data     { $_[0]->{streams}{$_[1]}{response_data} }
sub response_trailers { $_[0]->{streams}{$_[1]}{response_trailers} }
sub is_closed         { $_[0]->{streams}{$_[1]}{closed} }
sub is_cancelled      { $_[0]->{streams}{$_[1]}{cancelled} }
sub data_chunks       { $_[0]->{streams}{$_[1]}{data_chunks} }

sub close {
    my ($self) = @_;
    return unless $self->{mojo_stream};
    # Remove event handlers to prevent interference with future event loops
    $self->{mojo_stream}->unsubscribe('read');
    $self->{mojo_stream}->unsubscribe('error');
    $self->{mojo_stream}->unsubscribe('close');
    if ($self->{connected}) {
        $self->{con}->finish;
        $self->_flush();
    }
    $self->{mojo_stream}->close;
    $self->{mojo_stream} = undef;
    $self->{connected} = 0;
}

1;
