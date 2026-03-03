# Protobuf Conformance Testing

This document describes how ProtocolBuffers::PP integrates with the official
[protobuf conformance test suite](https://github.com/protocolbuffers/protobuf/tree/main/conformance).

## Quick Start

```bash
scripts/protobuf-conformance-test --protobuf-root /path/to/protobuf
```

The suite runs 2737 required tests across proto2 and proto3 message types,
exercising binary wire format round-tripping and ProtoJSON
serialization/deserialization.

## Current Status

| Category | Result |
|---|---|
| Required tests | 2737/2737 passing (0 unexpected failures) |
| Recommended tests | 33 warnings (non-blocking) |
| Edition tests | Skipped (not supported) |

The 33 recommended-test warnings cover features this implementation does not
support: proto2 extensions, unknown-enum ignore-and-skip semantics, and strict
FieldMask path validation.

## Architecture

The conformance suite uses a two-process architecture connected by pipes:

```
conformance_test_runner  ──stdin──▶  perl-conformance-harness
  (C++ binary)           ◀─stdout──   (Perl subprocess)
```

The runner is the driver: it generates test inputs, sends them to the harness,
reads back results, and compares against expected outputs.

### Wire Protocol

Communication uses a length-delimited protobuf framing protocol over
stdin/stdout:

```
┌─────────────────┬──────────────────────────────┐
│ 4 bytes (LE u32)│ N bytes (protobuf message)    │
│ message length  │ ConformanceRequest or Response │
└─────────────────┴──────────────────────────────┘
```

- Lengths are unsigned 32-bit little-endian integers (`pack("V", ...)` /
  `unpack("V", ...)` in Perl).
- A zero-length message from the runner signals the harness to exit.
- The harness handles partial reads by looping until the full payload arrives.

### Message Types

The protocol uses two protobuf messages defined in `conformance.proto`
(generated at test time into a temp directory):

**ConformanceRequest** — sent by the runner:

| Field | Description |
|---|---|
| `payload` (oneof) | Input data: `protobuf_payload` (bytes) or `json_payload` (string) |
| `requested_output_format` | Target format: PROTOBUF (1), JSON (2), JSPB (3), TEXT_FORMAT (4) |
| `message_type` | Fully-qualified proto type name |
| `test_category` | BINARY_TEST, JSON_TEST, JSON_IGNORE_UNKNOWN_PARSING_TEST, etc. |

**ConformanceResponse** — returned by the harness:

| Field (oneof `result`) | When used |
|---|---|
| `parse_error` | Input could not be decoded |
| `runtime_error` | Unexpected harness error |
| `protobuf_payload` | Successful protobuf output |
| `json_payload` | Successful JSON output |
| `skipped` | Unsupported format or message type |
| `serialize_error` | Output encoding failed |

## Components

### `scripts/protobuf-conformance-test` (entry point)

A bash wrapper that:

1. Accepts `--protobuf-root DIR` (or `$PROTOBUF_ROOT` env var) pointing to
   the protobuf source tree.
2. Creates a temp directory (cleaned up on exit).
3. Runs `protoc` with `protoc-gen-perl` to generate all needed types (WKTs,
   test messages, conformance protocol) into the temp directory.
4. Locates `conformance_test_runner` — checks
   `$PROTOBUF_ROOT/bazel-bin/conformance/conformance_test_runner`, then `$PATH`.
5. Runs the conformance test runner with `PROTOBUF_PP_GENDIR` set to the
   temp directory, passing through any extra arguments.

The `--failure_list` flag points to `conformance/protobuf-known-failing.txt`,
which lists test names expected to fail. This file is currently **empty** —
all required tests pass.

### `script/perl-conformance-harness` (test harness)

The Perl subprocess that implements the conformance protocol. On startup it:

1. Loads runtime modules (Encode, Decode, JSON::Print, JSON::Parse, Error).
2. Loads generated code from `$PROTOBUF_PP_GENDIR` (falling back to
   `../lib`) for Well-Known Types, test messages, and the Conformance
   protocol messages via `do`.
3. Builds a **type registry** by recursively walking message descriptors,
   needed for `google.protobuf.Any` resolution during JSON processing.
4. Sets STDIN/STDOUT to `:raw` binary mode.
5. Enters the main read-process-write loop.

**Request processing** (`process_request` subroutine):

1. Decode the `ConformanceRequest` from protobuf bytes.
2. Handle the special `conformance.FailureSet` request (returns an empty set).
3. Look up the `message_type` in the registry; skip unsupported types.
4. Skip unsupported output formats (JSPB, TEXT_FORMAT).
5. Decode the input payload based on the oneof discriminator:
   - Case 1 (`protobuf_payload`): binary decode via `decode_message`.
   - Case 2 (`json_payload`): JSON parse via `JSON::Parse::parse_message`.
     Passes `ignore_unknown_fields => 1` for `JSON_IGNORE_UNKNOWN_PARSING_TEST`.
   - Cases 7, 8 (JSPB, text): skipped.
6. Encode the message to the requested output format:
   - PROTOBUF (1): `encode_message` → `protobuf_payload` response.
   - JSON (2): `JSON::Print::print_message` → `json_payload` response.
7. Errors at any stage are caught with `eval {}` and returned as
   `parse_error`, `serialize_error`, or `runtime_error`.

### Generated Code

The harness loads these generated packages:

| Package | Source proto | Purpose |
|---|---|---|
| `Conformance::ConformanceRequest` | `conformance.proto` | Request message definition |
| `Conformance::ConformanceResponse` | `conformance.proto` | Response message definition |
| `Conformance::FailureSet` | `conformance.proto` | Expected failures (empty) |
| `Protobuf_test_messages::Proto3::TestAllTypesProto3` | `test_messages_proto3.proto` | Proto3 test message |
| `Protobuf_test_messages::Proto2::TestAllTypesProto2` | `test_messages_proto2.proto` | Proto2 test message |
| `Google::Protobuf::Any` | `any.proto` | WKT |
| `Google::Protobuf::Timestamp` | `timestamp.proto` | WKT |
| `Google::Protobuf::Duration` | `duration.proto` | WKT |
| `Google::Protobuf::FieldMask` | `field_mask.proto` | WKT |
| `Google::Protobuf::*Value` | `wrappers.proto` | WKT wrappers |
| `Google::Protobuf::Struct`, `Value`, `ListValue` | `struct.proto` | WKT |

### Type Registry

A hash mapping fully-qualified proto type names to descriptors and Perl
classes. Built at startup by walking all loaded message descriptors. Required
for `google.protobuf.Any` type resolution — when the JSON serializer/parser
encounters an Any, it looks up the `type_url` in this registry to find the
correct descriptor for packing/unpacking.

### Failure List (`conformance/protobuf-known-failing.txt`)

A newline-delimited list of test names that are expected to fail. The
`conformance_test_runner` treats these as "known failures" — they don't count
against the pass/fail result. Currently empty.

## Prerequisites

### Protobuf Source Tree

The wrapper script needs access to the protobuf source tree (for proto
include files and the conformance runner binary). Clone and build it:

```bash
git clone https://github.com/protocolbuffers/protobuf.git
cd protobuf
bazel build //conformance:conformance_test_runner
```

The wrapper script looks for the runner at
`$PROTOBUF_ROOT/bazel-bin/conformance/conformance_test_runner`, then falls
back to `$PATH`.

### `protoc` Compiler

The `protoc` compiler must be on `$PATH`. It is used by the wrapper script
to generate Perl types into a temp directory before each run.

## Debugging

The harness redirects STDERR to `/tmp/perl-conformance-harness.log`. Any
`warn` or diagnostic output goes there instead of interfering with the
binary pipe protocol on stdout.

To debug a specific test failure, check the log after a run:

```bash
scripts/protobuf-conformance-test --protobuf-root /path/to/protobuf
cat /tmp/perl-conformance-harness.log
```

## Data Flow Example

A single test iteration:

```
1. Runner generates a ConformanceRequest:
   - message_type: "protobuf_test_messages.proto3.TestAllTypesProto3"
   - protobuf_payload: <binary bytes encoding some test fields>
   - requested_output_format: JSON

2. Runner writes to harness stdin:
   [4-byte LE length][protobuf-encoded ConformanceRequest]

3. Harness reads and decodes the ConformanceRequest.

4. Harness decodes protobuf_payload into a Perl hash
   using the TestAllTypesProto3 descriptor.

5. Harness serializes the hash to JSON using JSON::Print.

6. Harness builds a ConformanceResponse with json_payload set.

7. Harness writes to stdout:
   [4-byte LE length][protobuf-encoded ConformanceResponse]

8. Runner reads the response, compares the JSON output
   against the expected value, and records pass/fail.
```
