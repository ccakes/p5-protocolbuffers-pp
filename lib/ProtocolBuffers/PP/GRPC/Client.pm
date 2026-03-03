package ProtocolBuffers::PP::GRPC::Client;
use strict;
use warnings;
use MIME::Base64 ();
use Time::HiRes ();
use Mojo::IOLoop;
use ProtocolBuffers::PP::GRPC::Transport;
use ProtocolBuffers::PP::GRPC::Status qw(:all);

sub new {
    my ($class, %opts) = @_;
    return bless {
        host     => $opts{host} || 'localhost',
        port     => $opts{port} || 50051,
        timeout  => $opts{timeout},
        metadata => $opts{metadata} || [],
    }, $class;
}

# ---- Public RPC methods ----

sub unary {
    my ($self, $path, $request_bytes, %opts) = @_;
    my $transport = $self->_new_transport();
    my $stream_id = $self->_start_stream($transport, $path, %opts);

    my $frame = _encode_grpc_frame($request_bytes);
    $transport->send_data($stream_id, $frame);
    $transport->close_send($stream_id);

    $self->_handle_cancel($transport, $stream_id, $opts{cancel});
    $self->_setup_timeout($transport, $stream_id, %opts);
    $transport->pump_until(sub { $transport->is_closed($stream_id) });

    my $result = $self->_build_result($transport, $stream_id);
    $result = _validate_unary_response($result);
    $transport->close();
    return $result;
}

sub server_stream {
    my ($self, $path, $request_bytes, %opts) = @_;
    my $transport = $self->_new_transport();
    my $stream_id = $self->_start_stream($transport, $path, %opts);

    my $frame = _encode_grpc_frame($request_bytes);
    $transport->send_data($stream_id, $frame);
    $transport->close_send($stream_id);

    $self->_handle_cancel($transport, $stream_id, $opts{cancel});
    $self->_setup_timeout($transport, $stream_id, %opts);
    $transport->pump_until(sub { $transport->is_closed($stream_id) });

    my $result = $self->_build_result($transport, $stream_id);
    $transport->close();
    return $result;
}

sub client_stream {
    my ($self, $path, $request_list, %opts) = @_;
    my $transport = $self->_new_transport();
    my $stream_id = $self->_start_stream($transport, $path, %opts);
    my $delay_ms  = $opts{request_delay_ms} || 0;
    my $cancel    = $opts{cancel};

    $self->_setup_timeout($transport, $stream_id, %opts);

    if ($delay_ms > 0) {
        # Send requests with delays between them
        my @reqs   = @$request_list;
        my $cancelled = 0;

        my $send_next;
        $send_next = sub {
            return if $cancelled;
            if (@reqs) {
                my $req = shift @reqs;
                $transport->send_data($stream_id, _encode_grpc_frame($req));

                if ($cancel && defined $cancel->{before_close_send} && !@reqs) {
                    $transport->cancel($stream_id);
                    $cancelled = 1;
                    Mojo::IOLoop->stop;
                    return;
                }

                if (@reqs) {
                    Mojo::IOLoop->timer($delay_ms / 1000 => $send_next);
                } else {
                    $transport->close_send($stream_id);
                    $self->_handle_cancel_post_close($transport, $stream_id, $cancel);
                }
            }
        };
        Mojo::IOLoop->next_tick($send_next);

        $transport->pump_until(sub { $transport->is_closed($stream_id) || $cancelled });
    } else {
        for my $req_bytes (@$request_list) {
            $transport->send_data($stream_id, _encode_grpc_frame($req_bytes));
        }

        if ($cancel && defined $cancel->{before_close_send}) {
            $transport->cancel($stream_id);
            $transport->pump_until(sub { $transport->is_closed($stream_id) });
            my $result = $self->_build_result($transport, $stream_id);
            $transport->close();
            return $result;
        }

        $transport->close_send($stream_id);
        $self->_handle_cancel_post_close($transport, $stream_id, $cancel);
        $transport->pump_until(sub { $transport->is_closed($stream_id) });
    }

    my $result = $self->_build_result($transport, $stream_id);
    $result = _validate_unary_response($result);
    $transport->close();
    return $result;
}

sub bidi_stream {
    my ($self, $path, $requests, %opts) = @_;
    my $full_duplex = $opts{full_duplex} || 0;
    my $transport   = $self->_new_transport();
    my $stream_id   = $self->_start_stream($transport, $path, %opts);
    my $delay_ms    = $opts{request_delay_ms} || 0;
    my $cancel      = $opts{cancel};

    $self->_setup_timeout($transport, $stream_id, %opts);

    if ($full_duplex) {
        return $self->_bidi_full_duplex(
            $transport, $stream_id, $requests, $delay_ms, $cancel
        );
    } else {
        return $self->_bidi_half_duplex(
            $transport, $stream_id, $requests, $delay_ms, $cancel
        );
    }
}

# ---- Internal helpers ----

sub _new_transport {
    my ($self) = @_;
    return ProtocolBuffers::PP::GRPC::Transport->new($self->{host}, $self->{port});
}

sub _start_stream {
    my ($self, $transport, $path, %opts) = @_;

    my @headers = (
        ':method'       => 'POST',
        ':scheme'       => 'http',
        ':path'         => $path,
        ':authority'    => "$self->{host}:$self->{port}",
        'content-type'  => 'application/grpc+proto',
        'te'            => 'trailers',
    );

    # Timeout
    my $timeout = $opts{timeout} || $self->{timeout};
    if ($timeout) {
        push @headers, 'grpc-timeout' => "${timeout}m";
    }

    # User-provided metadata
    # Note: binary header values (-bin suffix) are expected to be already
    # base64-encoded, matching the gRPC wire format convention.
    if ($opts{headers}) {
        for my $h (@{$opts{headers}}) {
            my $name = $h->[0];
            for my $val (@{$h->[1]}) {
                push @headers, $name => $val;
            }
        }
    }

    return $transport->new_stream(\@headers);
}

# Client-side deadline enforcement
sub _setup_timeout {
    my ($self, $transport, $stream_id, %opts) = @_;
    my $timeout = $opts{timeout} || $self->{timeout};
    return unless $timeout;
    # Store absolute deadline so _build_result can detect expired deadlines
    # even if the timer hasn't fired yet (e.g. server RST_STREAMs first).
    $transport->{streams}{$stream_id}{deadline_at} = Time::HiRes::time() + ($timeout / 1000);
    Mojo::IOLoop->timer($timeout / 1000 => sub {
        unless ($transport->is_closed($stream_id)) {
            $transport->cancel($stream_id);
            $transport->{streams}{$stream_id}{deadline_exceeded} = 1;
        }
    });
}

sub _handle_cancel {
    my ($self, $transport, $stream_id, $cancel) = @_;
    return unless $cancel;

    if (defined $cancel->{after_close_send_ms}) {
        Mojo::IOLoop->timer($cancel->{after_close_send_ms} / 1000 => sub {
            $transport->cancel($stream_id) unless $transport->is_closed($stream_id);
        });
    }

    if (defined $cancel->{after_num_responses}) {
        my $target = $cancel->{after_num_responses};
        $self->_setup_response_count_cancel($transport, $stream_id, $target);
    }
}

sub _handle_cancel_post_close {
    my ($self, $transport, $stream_id, $cancel) = @_;
    return unless $cancel;
    $self->_handle_cancel($transport, $stream_id, $cancel);
}

sub _setup_response_count_cancel {
    my ($self, $transport, $stream_id, $target) = @_;
    my $check_id;
    $check_id = Mojo::IOLoop->recurring(0.01 => sub {
        my $data = $transport->response_data($stream_id) // '';
        my $count = _count_grpc_frames($data);
        if ($count >= $target && !$transport->is_closed($stream_id)) {
            $transport->cancel($stream_id);
            Mojo::IOLoop->remove($check_id);
        }
        if ($transport->is_closed($stream_id)) {
            Mojo::IOLoop->remove($check_id);
        }
    });
}

sub _build_result {
    my ($self, $transport, $stream_id) = @_;

    my $resp_headers  = $transport->response_headers($stream_id);
    my $resp_data     = $transport->response_data($stream_id) // '';
    my $resp_trailers = $transport->response_trailers($stream_id);

    my ($grpc_status, $grpc_message, $status_details_bin);
    my @messages;

    # Validate content-type header
    if ($resp_headers) {
        my %hh = _headers_to_hash($resp_headers);
        my $ct = $hh{'content-type'} // '';
        if ($ct ne '' && $ct !~ m{^application/grpc(?:\+proto)?(?:;|$)}) {
            # Wrong content-type on a 200 response → UNKNOWN
            return {
                messages   => [],
                headers    => _parse_metadata($resp_headers),
                trailers   => _parse_metadata($resp_trailers),
                grpc_status => UNKNOWN,
                grpc_message => "unexpected content-type: $ct",
            };
        }

        # Validate grpc-encoding (compression)
        my $enc = $hh{'grpc-encoding'} // '';
        if ($enc ne '' && $enc ne 'identity') {
            return {
                messages   => [],
                headers    => _parse_metadata($resp_headers),
                trailers   => _parse_metadata($resp_trailers),
                grpc_status => INTERNAL,
                grpc_message => "unexpected grpc-encoding: $enc",
            };
        }
    }

    # Decode gRPC frames, checking for unexpected compression
    my $decode_err;
    ($decode_err, @messages) = _decode_grpc_frames_checked($resp_data);
    if ($decode_err) {
        return {
            messages   => [],
            headers    => _parse_metadata($resp_headers),
            trailers   => _parse_metadata($resp_trailers),
            grpc_status => INTERNAL,
            grpc_message => $decode_err,
        };
    }

    # Determine trailers-only vs normal response.
    # A trailers-only response has grpc-status in the initial HEADERS
    # with no DATA body. If initial HEADERS has grpc-status but there
    # IS a DATA body, ignore the initial HEADERS' grpc-status.
    my $initial_has_grpc_status = 0;
    if ($resp_headers) {
        my %hh = _headers_to_hash($resp_headers);
        $initial_has_grpc_status = defined $hh{'grpc-status'};
    }

    if ($resp_trailers) {
        # Normal response with separate trailers
        my %th = _headers_to_hash($resp_trailers);
        $grpc_status = $th{'grpc-status'};
        $grpc_message = defined $th{'grpc-message'}
            ? _percent_decode($th{'grpc-message'}) : undef;
        if (defined $th{'grpc-status-details-bin'}) {
            $status_details_bin = MIME::Base64::decode_base64($th{'grpc-status-details-bin'});
        }
    } elsif ($initial_has_grpc_status && length($resp_data) == 0) {
        # Trailers-only: grpc-status in initial HEADERS, no DATA body
        my %th = _headers_to_hash($resp_headers);
        $grpc_status = $th{'grpc-status'};
        $grpc_message = defined $th{'grpc-message'}
            ? _percent_decode($th{'grpc-message'}) : undef;
        if (defined $th{'grpc-status-details-bin'}) {
            $status_details_bin = MIME::Base64::decode_base64($th{'grpc-status-details-bin'});
        }
    } elsif ($initial_has_grpc_status && length($resp_data) > 0) {
        # Invalid: grpc-status in initial HEADERS but DATA body present.
        # Per gRPC spec, ignore the initial grpc-status; report INTERNAL.
        $grpc_status = INTERNAL;
        @messages = ();
    }

    # Map HTTP status codes to gRPC errors when no grpc-status is present
    if (!defined $grpc_status && $resp_headers) {
        my %hh = _headers_to_hash($resp_headers);
        my $http_status = $hh{':status'};
        if (defined $http_status && $http_status ne '200') {
            $grpc_status = _http_to_grpc_status($http_status);
        }
    }

    # If no gRPC status was received and deadline was exceeded, synthesize.
    # Check both the flag (set by timer callback) and the stored deadline
    # timestamp (covers the race where the server closes the stream before
    # our timer fires).
    if (!defined $grpc_status) {
        my $st = $transport->{streams}{$stream_id};
        if ($st->{deadline_exceeded}
            || (defined $st->{deadline_at} && Time::HiRes::time() >= $st->{deadline_at})) {
            $grpc_status = DEADLINE_EXCEEDED;
        }
    }

    # If no gRPC status was received and we cancelled, synthesize CANCELLED
    if (!defined $grpc_status && $transport->is_cancelled($stream_id)) {
        $grpc_status = CANCELLED;
    }

    # If stream closed without any gRPC status, report UNKNOWN
    if (!defined $grpc_status && $transport->is_closed($stream_id)) {
        $grpc_status = UNKNOWN;
    }

    # Parse header/trailer pairs for caller
    my $parsed_headers  = _parse_metadata($resp_headers);
    my $parsed_trailers = _parse_metadata($resp_trailers);

    return {
        messages            => \@messages,
        headers             => $parsed_headers,
        trailers            => $parsed_trailers,
        grpc_status         => $grpc_status,
        grpc_message        => $grpc_message,
        status_details_bin  => $status_details_bin,
    };
}

sub _bidi_half_duplex {
    my ($self, $transport, $stream_id, $requests, $delay_ms, $cancel) = @_;

    # Send all requests, then close send, then read all responses
    if ($delay_ms > 0) {
        my @reqs = @$requests;
        my $cancelled = 0;

        my $send_next;
        $send_next = sub {
            return if $cancelled;
            if (@reqs) {
                my $req = shift @reqs;
                $transport->send_data($stream_id, _encode_grpc_frame($req));

                if ($cancel && defined $cancel->{before_close_send} && !@reqs) {
                    $transport->cancel($stream_id);
                    $cancelled = 1;
                    Mojo::IOLoop->stop;
                    return;
                }

                if (@reqs) {
                    Mojo::IOLoop->timer($delay_ms / 1000 => $send_next);
                } else {
                    $transport->close_send($stream_id);
                    $self->_handle_cancel_post_close($transport, $stream_id, $cancel);
                }
            }
        };
        Mojo::IOLoop->next_tick($send_next);
        $transport->pump_until(sub { $transport->is_closed($stream_id) || $cancelled });
    } else {
        for my $req_bytes (@$requests) {
            $transport->send_data($stream_id, _encode_grpc_frame($req_bytes));
        }

        if ($cancel && defined $cancel->{before_close_send}) {
            $transport->cancel($stream_id);
            $transport->pump_until(sub { $transport->is_closed($stream_id) });
            my $result = $self->_build_result($transport, $stream_id);
            $transport->close();
            return $result;
        }

        $transport->close_send($stream_id);
        $self->_handle_cancel_post_close($transport, $stream_id, $cancel);
        $transport->pump_until(sub { $transport->is_closed($stream_id) });
    }

    my $result = $self->_build_result($transport, $stream_id);
    $transport->close();
    return $result;
}

sub _bidi_full_duplex {
    my ($self, $transport, $stream_id, $requests, $delay_ms, $cancel) = @_;

    # Full duplex: send a request, wait for a response, repeat.
    # This interleaves sends and receives as expected by the conformance tests.
    my @reqs = @$requests;
    my $cancelled     = 0;
    my $cancel_target = $cancel ? $cancel->{after_num_responses} : undef;

    for my $i (0 .. $#reqs) {
        last if $cancelled || $transport->is_closed($stream_id);

        # Optional delay before send (except first)
        if ($delay_ms > 0 && $i > 0) {
            my $delayed = 0;
            Mojo::IOLoop->timer($delay_ms / 1000 => sub {
                $delayed = 1;
                Mojo::IOLoop->stop;
            });
            Mojo::IOLoop->start unless $delayed;
        }

        # Send request
        $transport->send_data($stream_id, _encode_grpc_frame($reqs[$i]));

        # Wait for response to this request
        my $expected = $i + 1;
        $transport->pump_until(sub {
            my $data = $transport->response_data($stream_id) // '';
            my $count = _count_grpc_frames($data);
            return 1 if $count >= $expected;
            return 1 if $transport->is_closed($stream_id);
            return 1 if $cancelled;
            return 0;
        });

        last if $transport->is_closed($stream_id) || $cancelled;

        # Check cancel after N responses
        if (defined $cancel_target) {
            my $data = $transport->response_data($stream_id) // '';
            my $count = _count_grpc_frames($data);
            if ($count >= $cancel_target) {
                $transport->cancel($stream_id);
                $cancelled = 1;
                last;
            }
        }
    }

    # Handle post-send cancel/close
    if (!$cancelled && !$transport->is_closed($stream_id)) {
        if ($cancel && defined $cancel->{before_close_send}) {
            $transport->cancel($stream_id);
            $cancelled = 1;
        } else {
            $transport->close_send($stream_id);

            if ($cancel && defined $cancel->{after_close_send_ms}) {
                Mojo::IOLoop->timer($cancel->{after_close_send_ms} / 1000 => sub {
                    $transport->cancel($stream_id)
                        unless $transport->is_closed($stream_id);
                });
            }

            # Wait for stream to close
            $transport->pump_until(sub {
                $transport->is_closed($stream_id) || $cancelled
            });
        }
    }

    my $result = $self->_build_result($transport, $stream_id);
    $transport->close();
    return $result;
}

# ---- gRPC framing ----

sub _encode_grpc_frame {
    my ($payload) = @_;
    # 1 byte compressed flag (0) + 4 byte big-endian length + payload
    return pack('CN', 0, length($payload)) . $payload;
}

sub _decode_grpc_frames {
    my ($data) = @_;
    my @messages;
    my $pos = 0;
    while ($pos + 5 <= length($data)) {
        my ($compressed, $len) = unpack('CN', substr($data, $pos, 5));
        last if $pos + 5 + $len > length($data);
        push @messages, substr($data, $pos + 5, $len);
        $pos += 5 + $len;
    }
    return @messages;
}

# Like _decode_grpc_frames but returns (error, @messages).
# Returns error string if a compressed frame is found (we don't support compression).
sub _decode_grpc_frames_checked {
    my ($data) = @_;
    my @messages;
    my $pos = 0;
    while ($pos + 5 <= length($data)) {
        my ($compressed, $len) = unpack('CN', substr($data, $pos, 5));
        last if $pos + 5 + $len > length($data);
        if ($compressed) {
            return ("received compressed message but compression not negotiated");
        }
        push @messages, substr($data, $pos + 5, $len);
        $pos += 5 + $len;
    }
    return (undef, @messages);
}

sub _count_grpc_frames {
    my ($data) = @_;
    my $count = 0;
    my $pos   = 0;
    while ($pos + 5 <= length($data)) {
        my ($compressed, $len) = unpack('CN', substr($data, $pos, 5));
        last if $pos + 5 + $len > length($data);
        $count++;
        $pos += 5 + $len;
    }
    return $count;
}

# ---- Metadata helpers ----

sub _headers_to_hash {
    my ($headers) = @_;
    return () unless $headers && ref $headers eq 'ARRAY';
    my %h;
    for (my $i = 0; $i < @$headers; $i += 2) {
        $h{$headers->[$i]} = $headers->[$i + 1];
    }
    return %h;
}

sub _parse_metadata {
    my ($headers) = @_;
    return [] unless $headers && ref $headers eq 'ARRAY';
    my @result;
    my %seen;
    for (my $i = 0; $i < @$headers; $i += 2) {
        my $name = $headers->[$i];
        my $val  = $headers->[$i + 1];
        # Skip pseudo-headers
        next if $name =~ /^:/;
        # Binary header values (-bin suffix) are kept as base64-encoded
        # strings from the wire, matching the gRPC convention.
        if (exists $seen{$name}) {
            # Append to existing header entry
            push @{$seen{$name}[1]}, $val;
        } else {
            my $entry = [$name, [$val]];
            push @result, $entry;
            $seen{$name} = $entry;
        }
    }
    return \@result;
}

sub _percent_decode {
    my ($str) = @_;
    $str =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/ge;
    return $str;
}

# Validate that a unary/client-stream RPC received exactly one response.
# Called after _build_result for unary() and client_stream().
sub _validate_unary_response {
    my ($result) = @_;
    my $status = $result->{grpc_status};
    # Only validate when the server reported OK
    return $result unless defined $status && $status == 0;
    my $count = scalar @{$result->{messages} || []};
    if ($count != 1) {
        $result->{grpc_status} = UNIMPLEMENTED;
        $result->{grpc_message} = $count == 0
            ? "unary RPC completed with no response message"
            : "unary RPC completed with $count response messages";
        $result->{messages} = [];
    }
    return $result;
}

# Map HTTP status codes to gRPC status codes per the gRPC spec
sub _http_to_grpc_status {
    my ($http_status) = @_;
    my %mapping = (
        400 => INTERNAL,
        401 => UNAUTHENTICATED,
        403 => PERMISSION_DENIED,
        404 => UNIMPLEMENTED,
        429 => UNAVAILABLE,
        502 => UNAVAILABLE,
        503 => UNAVAILABLE,
        504 => UNAVAILABLE,
    );
    return $mapping{$http_status} // UNKNOWN;
}

1;
