#!/usr/bin/env perl

use v5.36;
use strict;
use warnings;

use FindBin;
use lib "$FindBin::RealBin/lib";
use lib "$FindBin::RealBin/../lib";

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

# --- Unary RPC ---
say "=== SayHello (unary) ===";
my $response = $client->SayHello({ greeting => 'Perl' });
say "  Sent:     Perl";
say "  Received: $response->{reply}\n";

# --- Server streaming RPC (sync) ---
say "=== LotsOfReplies (server streaming, sync) ===";
my $replies = $client->LotsOfReplies({ greeting => 'Stream-ee' });
say "  Sent:    Stream-ee";
for my $i (0 .. $#$replies) {
    say "  Reply ${\($i+1)}: $replies->[$i]{reply}";
}
say "\n";

# --- Server streaming RPC (async with callbacks) ---
say "=== LotsOfReplies (server streaming, async) ===";
my $reply_num = 0;
my $call = $client->LotsOfReplies(
    { greeting => 'Async-ee' },
    on_message => sub ($msg) { $reply_num++; say "  Reply $reply_num: $msg->{reply}" },
    on_close   => sub ($status, $msg, @) { say "  Stream closed (status=$status)" },
);
$call->wait;
say "\n";

# --- Client streaming RPC (sync) ---
say "=== LotsOfGreetings (client streaming, sync) ===";
say "  Sent:     Stream-er #1..5";
my @greetings = map { { greeting => "Stream-er #$_" } } 1 .. 5;
my $summary = $client->LotsOfGreetings(\@greetings);
say "  Received: $summary->{reply}\n";

# --- Client streaming RPC (async) ---
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
