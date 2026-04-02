#!/usr/bin/env perl

use v5.36;
use strict;
use warnings;

use FindBin;
use lib "$FindBin::RealBin/lib";
use lib "$FindBin::RealBin/../../lib";

use ProtocolBuffers::PP::GRPC::Client;

# Load generated types (includes HelloService::Client)
require "$FindBin::RealBin/lib/Postman-echo.pm";

# Create gRPC channel (plaintext h2c — the server does not use TLS)
my $channel = ProtocolBuffers::PP::GRPC::Client->new(
    host    => 'grpc.postman-echo.com',
    port    => 443,
    timeout => 10000,
);

# Create typed service client
my $client = HelloService::Client->new(channel => $channel);

=head1 RPC Types

=head2 Unary RPC

First consider the simplest type of RPC where the client sends a single request
and gets back a single response.

=cut

say "=== SayHello (unary) ===";
my $response = $client->SayHello({ greeting => 'Perl' });
say "  Sent:     Perl";
say "  Received: $response->{reply}\n";

=head2 Server streaming RPC

A server-streaming RPC is similar to a unary RPC, except that the server returns
a stream of messages in response to a client’s request. After sending all its
messages, the server’s status details (status code and optional status message)
and optional trailing metadata are sent to the client. This completes processing
on the server side. The client completes once it has all the server’s messages.

=head3 Synchronous

The sync interface sends the client -> server message and then waits for the
server to close the request before returning an arrayref of response messages.

=cut

say "=== LotsOfReplies (server streaming, sync) ===";
my $replies = $client->LotsOfReplies({ greeting => 'Stream-ee' });
say "  Sent:    Stream-ee";
for my $i (0 .. $#$replies) {
    say "  Reply ${\($i+1)}: $replies->[$i]{reply}";
}
say "\n";

=head3 Asynchronous

The async interface allows the caller to register callbacks for C<on_message>
and C<on_close>. C<on_message> is called for each received message in the
stream and C<on_close> is called when the server closes the stream or on error.

=cut

say "=== LotsOfReplies (server streaming, async) ===";
my $reply_num = 0;
my $call = $client->LotsOfReplies(
    { greeting => 'Async-ee' },
    on_message => sub ($msg) { $reply_num++; say "  Reply $reply_num: $msg->{reply}" },
    on_close   => sub ($status, $msg, @) { say "  Stream closed (status=$status)" },
);
$call->wait;
say "\n";

=head2 Client streaming RPC

A client-streaming RPC is similar to a unary RPC, except that the client sends a
stream of messages to the server instead of a single message. The server responds
with a single message (along with its status details and optional trailing
metadata), typically but not necessarily after it has received all the client's
messages.

=head3 Synchronous

The sync interface sends the full list of client -> server messages at once and
waits for the server response before returning.

=cut

say "=== LotsOfGreetings (client streaming, sync) ===";
say "  Sent:     Stream-er #1..5";
my @greetings = map { { greeting => "Stream-er #$_" } } 1 .. 5;
my $summary = $client->LotsOfGreetings(\@greetings);
say "  Received: $summary->{reply}\n";

=head3 Asynchronous

The async interface allows the caller to register the same C<on_message> and
C<on_error> callbacks. The caller can also use the C<send> method to send
messages to the server on the stream.

=cut

say "=== LotsOfGreetings (client streaming, async) ===";
my $cs_call = $client->LotsOfGreetings(
    on_message => sub ($msg) { say "  Received: $msg->{reply}" },
    on_close   => sub ($status, @) { say "  Stream closed (status=$status)" },
);
for my $i (1 .. 3) {
    say "  Sending: Async-er #$i";
    $cs_call->send({ greeting => "Async-er #$i" });
}
$cs_call->close_send;
$cs_call->wait;
