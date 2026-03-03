# ProtocolBuffers::PP

A **pure Perl** implementation of [Google Protocol Buffers](https://protobuf.dev/) with full proto2/proto3 support, canonical JSON mapping, a `protoc` code generator plugin, and a gRPC client.

Passes **all 2737 required tests** in the official protobuf conformance suite and **all 211 tests** in the ConnectRPC gRPC conformance suite.

## Features

- **Binary wire format** encoding and decoding (varint, zigzag, fixed-width, length-delimited, groups)
- **Canonical JSON mapping** (ProtoJSON) with proper lowerCamelCase field names, int64-as-string, bytes-as-base64, enum-as-name
- **Well-Known Types** with special JSON representations: Timestamp, Duration, FieldMask, Any, Struct/Value/ListValue, Wrappers
- **gRPC client** over HTTP/2 with unary, client-streaming, server-streaming, and bidirectional streaming support
- **`protoc-gen-perl`** plugin generates Perl packages from `.proto` files
- **No XS or compiled extensions** required

## Requirements

- Perl 5.20+ (64-bit integer support required)
- `protoc` compiler (for code generation)
- Core modules: JSON::PP, MIME::Base64, Math::BigInt, POSIX

## Installation

```bash
# Install dependencies
cpanm --installdeps .

# Or manually:
cpanm JSON::PP MIME::Base64 Math::BigInt
```

## Usage

### Code Generation

Generate Perl packages from `.proto` files using `protoc`:

```bash
protoc --perl_out=lib/ --plugin=protoc-gen-perl=script/protoc-gen-perl \
    -I /path/to/proto/includes your_message.proto
```

This produces Perl packages under `lib/` mirroring the proto package structure.

### Encoding and Decoding

```perl
use ProtocolBuffers::PP::Encode qw(encode_message);
use ProtocolBuffers::PP::Decode qw(decode_message);

# Load your generated message class
use Your::Proto::Message;

my $desc = Your::Proto::Message->__DESCRIPTOR__;

# Encode
my $msg = { name => "example", id => 42 };
my $bytes = encode_message($msg, $desc);

# Decode
my $decoded = decode_message($desc, $bytes, $desc);
```

### JSON Serialization

```perl
use ProtocolBuffers::PP::JSON::Print;
use ProtocolBuffers::PP::JSON::Parse;

# Message -> JSON string
my $json = ProtocolBuffers::PP::JSON::Print::print_message($msg, $desc);

# JSON string -> Message
my $parsed = ProtocolBuffers::PP::JSON::Parse::parse_message($json, $desc);
```

## Project Layout

| Directory | Contents |
|---|---|
| `lib/ProtocolBuffers/PP/` | Runtime: encoding, decoding, JSON mapping, gRPC client, wire format, WKT helpers |
| `lib/ProtocolBuffers/Generated/` | Base classes for generated message/enum code |
| `script/` | `protoc-gen-perl` plugin, conformance harness and gRPC client |
| `scripts/` | Conformance test wrapper scripts (protobuf and gRPC) |
| `conformance/` | Conformance config and known-failing lists |
| `docs/` | Feature documentation |
| `t/unit/` | Unit tests |

## Testing

```bash
# Run unit tests
prove -r t/unit/

# Run the official protobuf conformance suite
scripts/protobuf-conformance-test --protobuf-root /path/to/protobuf

# Run the gRPC conformance suite
scripts/grpc-conformance-test --connectrpc-root /path/to/connectrpc-conformance
```

The conformance wrapper scripts generate types into a temp directory via
`protoc` and locate the test runner binary automatically. See
[docs/protobuf-conformance.md](docs/protobuf-conformance.md) and
[docs/grpc-conformance.md](docs/grpc-conformance.md) for details.

## Conformance Status

| Suite | Result |
|-------|--------|
| Protobuf required tests | **2737/2737 passing** |
| Protobuf recommended tests | 33 warnings (non-blocking) |
| gRPC conformance tests | **211/211 passing** |

## License

Same terms as Perl itself.
