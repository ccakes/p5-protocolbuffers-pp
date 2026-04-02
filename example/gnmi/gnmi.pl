#!/usr/bin/env perl

use v5.36;
use strict;
use warnings;

use FindBin;
use lib "$FindBin::RealBin/lib";
use lib "$FindBin::RealBin/../../lib";

use Getopt::Long;
use JSON::PP;

use ProtocolBuffers::PP::GRPC::Client;

# Load generated gNMI types (includes Gnmi::GNMI::Client)
use Gnmi;

my $host;
my $port = 6030;
my $tls  = 0;
my $timeout = 10000;
my $do_capabilities;
my $get_path;
my $encoding = 'JSON_IETF';
my $username = $ENV{GNMI_USERNAME};
my $password = $ENV{GNMI_PASSWORD};

GetOptions(
    'host=s'         => \$host,
    'port=i'         => \$port,
    'tls!'           => \$tls,
    'timeout=i'      => \$timeout,
    'capabilities'   => \$do_capabilities,
    'get=s'          => \$get_path,
    'encoding=s'     => \$encoding,
    'username=s'     => \$username,
    'password=s'     => \$password,
) or usage();

usage() unless defined $host;
usage() unless $do_capabilities || defined $get_path;

# Allow --host host:port syntax
if ($host =~ /^(.+):([0-9]+)$/) {
    $host = $1;
    $port = $2;
}

# Build metadata headers for authentication
my @metadata;
if (defined $username && defined $password) {
    push @metadata, ['username', [$username]];
    push @metadata, ['password', [$password]];
}

# Create gRPC channel
my $channel = ProtocolBuffers::PP::GRPC::Client->new(
    host     => $host,
    port     => $port,
    tls      => $tls,
    timeout  => $timeout,
    metadata => \@metadata,
);

# Create typed gNMI service client
my $client = Gnmi::GNMI::Client->new(channel => $channel);

my $json = JSON::PP->new->utf8->pretty->canonical;

if ($do_capabilities) {
    do_capabilities();
}

if (defined $get_path) {
    do_get($get_path);
}

sub do_capabilities {
    say "=== gNMI Capabilities ===\n";

    my $response = $client->Capabilities({});

    # gNMI version
    say "gNMI version: " . ($response->{gNMI_version} // 'unknown');
    say '';

    # Supported encodings
    my @enc_names;
    for my $enc (@{$response->{supported_encodings} // []}) {
        push @enc_names, Gnmi::Encoding->name_for($enc) // $enc;
    }
    say "Supported encodings: " . join(', ', @enc_names);
    say '';

    # Supported models
    my $models = $response->{supported_models} // [];
    say "Supported models (" . scalar(@$models) . "):";
    for my $model (@$models) {
        my $name    = $model->{name}         // '';
        my $org     = $model->{organization} // '';
        my $version = $model->{version}      // '';
        printf "  %-50s  %-30s  %s\n", $name, $org, $version;
    }
}

sub do_get {
    my ($xpath) = @_;

    say "=== gNMI Get: $xpath ===\n";

    # Parse xpath into Path elements
    # e.g. "/interfaces/interface[name=eth0]/state" becomes
    #   elem: [{name=>"interfaces"}, {name=>"interface", key=>{name=>"eth0"}}, {name=>"state"}]
    my $path = parse_xpath($xpath);

    # Resolve encoding name to enum value
    my $enc_val = Gnmi::Encoding->value_for($encoding);
    die "Unknown encoding '$encoding'. Valid: JSON, BYTES, PROTO, ASCII, JSON_IETF\n"
        unless defined $enc_val;

    my $request = {
        path     => [$path],
        encoding => $enc_val,
    };

    my $response = $client->Get($request);

    for my $notification (@{$response->{notification} // []}) {
        my $ts = $notification->{timestamp} // 0;
        say "Timestamp: $ts";

        # Print prefix if present
        if (my $prefix = $notification->{prefix}) {
            say "Prefix: " . format_path($prefix);
        }

        # Print updates
        for my $update (@{$notification->{update} // []}) {
            my $p = format_path($update->{path});
            my $val = format_typed_value($update->{val});
            say "  $p = $val";
        }

        # Print deletes
        for my $del (@{$notification->{delete} // []}) {
            say "  [deleted] " . format_path($del);
        }
        say '';
    }
}

# Parse an XPath-style gNMI path string into a Path message hash.
# Supports key selectors: /a/b[key=val]/c
sub parse_xpath {
    my ($xpath) = @_;

    $xpath =~ s{^/}{};    # strip leading slash
    return { elem => [] } if $xpath eq '';

    my @elems;
    for my $segment (split m{/}, $xpath) {
        my %keys;
        my $name = $segment;

        # Parse key selectors: element[key1=val1][key2=val2]
        if ($segment =~ s/^([^\[]+)//) {
            $name = $1;
            while ($segment =~ /\[([^=]+)=([^\]]*)\]/g) {
                $keys{$1} = $2;
            }
        }

        my $elem = { name => $name };
        $elem->{key} = \%keys if %keys;
        push @elems, $elem;
    }

    return { elem => \@elems };
}

# Format a Path message hash back into a human-readable XPath string.
sub format_path {
    my ($path) = @_;
    return '' unless $path;

    my @parts;
    for my $elem (@{$path->{elem} // []}) {
        my $s = $elem->{name} // '';
        if (my $keys = $elem->{key}) {
            for my $k (sort keys %$keys) {
                $s .= "[$k=$keys->{$k}]";
            }
        }
        push @parts, $s;
    }

    # Fall back to deprecated element field
    if (!@parts && $path->{element}) {
        @parts = @{$path->{element}};
    }

    return '/' . join('/', @parts);
}

# Format a TypedValue oneof into a displayable string.
sub format_typed_value {
    my ($val) = @_;
    return '<empty>' unless $val;

    # The oneof case tells us which field is set
    my $case = $val->{_oneof_case} // {};

    # value oneof is index 0
    my $field_num = $case->{0};

    if (!defined $field_num) {
        # Try to detect by checking which fields are present
        for my $key (qw(json_ietf_val json_val string_val int_val uint_val
                        bool_val bytes_val double_val float_val ascii_val
                        leaflist_val any_val proto_bytes decimal_val)) {
            if (exists $val->{$key}) {
                $field_num = $key;
                last;
            }
        }
    }

    return '<empty>' unless defined $field_num;

    # Map field numbers to names for lookup
    my %num_to_name = (
        1  => 'string_val',
        2  => 'int_val',
        3  => 'uint_val',
        4  => 'bool_val',
        5  => 'bytes_val',
        6  => 'float_val',
        7  => 'decimal_val',
        8  => 'leaflist_val',
        9  => 'any_val',
        10 => 'json_val',
        11 => 'json_ietf_val',
        12 => 'ascii_val',
        13 => 'proto_bytes',
        14 => 'double_val',
    );

    my $name = $num_to_name{$field_num} // $field_num;

    if ($name eq 'json_val' || $name eq 'json_ietf_val') {
        # JSON bytes - decode and pretty-print
        my $raw = $val->{$name};
        utf8::decode($raw) if defined $raw;
        return $raw // '<empty>';
    }
    elsif ($name eq 'string_val' || $name eq 'ascii_val') {
        return $val->{$name} // '';
    }
    elsif ($name eq 'bool_val') {
        return $val->{$name} ? 'true' : 'false';
    }
    elsif ($name =~ /^(int_val|uint_val|double_val|float_val)$/) {
        return $val->{$name} // 0;
    }
    else {
        return "(${name}) " . ($val->{$name} // '');
    }
}

sub usage {
    die <<'USAGE';
Usage: gnmi.pl --host HOST [OPTIONS] ACTION

Options:
  --host HOST          Target hostname or IP (required)
  --port PORT          Target gRPC port (default: 6030)
  --tls / --no-tls     Enable/disable TLS (default: off)
  --timeout MS         RPC timeout in milliseconds (default: 10000)
  --username USER      Username for authentication metadata
  --password PASS      Password for authentication metadata
  --encoding ENC       Encoding for Get requests (default: JSON_IETF)
                       Valid: JSON, BYTES, PROTO, ASCII, JSON_IETF

Actions (at least one required):
  --capabilities       Fetch and display device capabilities
  --get PATH           Get data at the given XPath
                       e.g. --get /interfaces/interface[name=eth0]/state

Examples:
  gnmi.pl --host router1 --capabilities
  gnmi.pl --host router1 --port 57400 --tls --get /system/state
  gnmi.pl --host router1 --username admin --password admin --capabilities --get /
USAGE
}
