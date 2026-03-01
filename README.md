# ProtocolBuffers::PP

A **pure Perl** implementation of [Google Protocol Buffers](https://protobuf.dev/) with full proto2/proto3 support, canonical JSON mapping, and a `protoc` code generator plugin.

Passes **all 2737 required tests** in the official protobuf conformance suite.

## Features

- **Binary wire format** encoding and decoding (varint, zigzag, fixed-width, length-delimited, groups)
- **Canonical JSON mapping** (ProtoJSON) with proper lowerCamelCase field names, int64-as-string, bytes-as-base64, enum-as-name
- **Well-Known Types** with special JSON representations: Timestamp, Duration, FieldMask, Any, Struct/Value/ListValue, Wrappers
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

## Project Structure

```
lib/
  ProtocolBuffers/
    PP.pm                    # Version
    PP/
      Encode.pm              # Binary protobuf encoder
      Decode.pm              # Binary protobuf decoder
      Generator.pm           # protoc-gen-perl code generator
      Bootstrap.pm           # Self-hosted descriptor decoding
      Types.pm               # Field type constants
      Util.pm                # Default values, helpers
      Error.pm               # Structured error handling
      JSON/
        Print.pm             # Message -> JSON
        Parse.pm             # JSON -> Message
      Wire/
        Varint.pm            # Variable-length integer encoding
        ZigZag.pm            # Signed integer zigzag encoding
        Bytes.pm             # Fixed-width and length-delimited encoding
        Tags.pm              # Field tag encoding/decoding
      Timestamp.pm           # google.protobuf.Timestamp helpers
      Duration.pm            # google.protobuf.Duration helpers
      FieldMask.pm           # google.protobuf.FieldMask helpers
      Any.pm                 # google.protobuf.Any helpers
    Generated/
      Base.pm                # Base class for generated code
      Message.pm             # Message base class
      Enum.pm                # Enum base class
      Map.pm                 # Map field support
script/
  protoc-gen-perl            # protoc plugin
  perl-conformance-harness   # Conformance test runner
t/
  unit/                      # Unit tests (225 tests)
  conformance/               # Conformance suite configuration
```

## Testing

```bash
# Run unit tests
prove -r t/unit/

# Run the official protobuf conformance suite (requires conformance_test_runner binary)
./conformance-runner
```

## Conformance Status

| Suite | Result |
|-------|--------|
| Required tests | **2737/2737 passing** |
| Recommended tests | 33 warnings (non-blocking) |
| Edition tests | Skipped (not supported) |

## License

Same terms as Perl itself.
