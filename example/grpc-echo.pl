#!/usr/bin/env perl
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
print "=== SayHello (unary) ===\n";
my $response = $client->SayHello({ greeting => 'Perl' });
print "  Sent:     Perl\n";
print "  Received: $response->{reply}\n\n";

# --- Server streaming RPC ---
print "=== LotsOfReplies (server streaming) ===\n";
my $replies = $client->LotsOfReplies({ greeting => 'Stream-ee' });
print "  Sent:    Stream-ee\n";
for my $i (0 .. $#$replies) {
    print "  Reply ${\($i+1)}: $replies->[$i]{reply}\n";
}
print "\n";

# --- Client streaming RPC (5 greetings) ---
print "=== LotsOfGreetings (client streaming, 5 messages) ===\n";
print "  Sent:     Stream-er #1..5\n";
my @greetings = map { { greeting => "Stream-er #$_" } } 1 .. 5;
my $summary = $client->LotsOfGreetings(\@greetings);
print "  Received: $summary->{reply}\n";
