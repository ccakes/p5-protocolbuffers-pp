# gRPC Conformance Testing

This document describes how to validate the ProtocolBuffers::PP gRPC client
implementation using the
[ConnectRPC conformance test suite](https://github.com/connectrpc/conformance).

## Quick Start

```bash
script/grpc-conformance-test --connectrpc-root /path/to/connectrpc-conformance
```

## Current Status

| Category | Result |
|---|---|
| Total tests | 211/211 passing (0 failures) |
| Known failing | 0 |

## Architecture

The ConnectRPC conformance suite uses a three-process architecture:

```
connectconformance (test runner)
    │
    ├── Reference server (connect-go, started by runner)
    │     Implements ConformanceService over HTTP/2
    │
    └── Client under test (our Perl process)
          Reads ClientCompatRequest from stdin
          Makes gRPC calls to the reference server
          Writes ClientCompatResponse to stdout
```

For client testing, the flow is:

1. The runner starts a **reference server** (connect-go based) for each server
   configuration group.
2. The runner starts our Perl client as a **single long-running subprocess**.
3. For each test case, the runner writes a `ClientCompatRequest` to the
   client's stdin.
4. The client makes the RPC to the reference server, then writes a
   `ClientCompatResponse` to stdout.
5. The runner compares the actual result against expected values.
6. When all tests finish, stdin reaches EOF. The client should exit cleanly.

## Wire Protocol (Runner <-> Client)

Communication uses **size-delimited protobuf messages** on stdin/stdout:

```
┌──────────────────┬──────────────────────────────────┐
│ 4 bytes (BE u32) │ N bytes (protobuf message)        │
│ message length   │ ClientCompatRequest or Response    │
└──────────────────┴──────────────────────────────────┘
```

**Important difference from protobuf conformance:** Length prefixes are
**big-endian** (network byte order), not little-endian. In Perl:
`pack("N", $len)` / `unpack("N", $buf)`.

- The runner writes `ClientCompatRequest` messages to client stdin.
- The client writes `ClientCompatResponse` messages to its stdout.
- Responses may be written out-of-order (the `test_name` field correlates
  responses to requests).
- When stdin reaches EOF, the client should finish in-progress RPCs and exit.
- If the client receives SIGTERM, it should exit immediately.
- Maximum response message size: 16 MB. Response timeout: 20 seconds per test.

## Proto Definitions

All conformance protos live in the ConnectRPC repository under
`proto/connectrpc/conformance/v1/`:

| File | Purpose |
|---|---|
| `client_compat.proto` | `ClientCompatRequest` / `ClientCompatResponse` — the runner-to-client protocol |
| `service.proto` | `ConformanceService` definition and all RPC request/response types |
| `config.proto` | `Config`, `Features`, enums (`Protocol`, `Codec`, `Compression`, `StreamType`, `Code`) |
| `server_compat.proto` | Server-side protocol (not needed for client testing) |
| `suite.proto` | Test suite / test case schema (YAML definitions) |

These are compiled with `protoc-gen-perl` into a temp directory at test time
by the `script/grpc-conformance-test` wrapper script.

## ConformanceService

The test service has 6 RPC methods:

| Method | Stream Type | Description |
|---|---|---|
| `Unary` | Unary | Standard request/response |
| `ServerStream` | Server streaming | One request, multiple responses |
| `ClientStream` | Client streaming | Multiple requests, one response |
| `BidiStream` | Bidirectional | Full-duplex or half-duplex streaming |
| `Unimplemented` | Unary | Must return UNIMPLEMENTED error |
| `IdempotentUnary` | Unary | Connect-only (GET); not applicable to gRPC |

The client must handle these stream types:

| Stream Type | Used By |
|---|---|
| `STREAM_TYPE_UNARY` | `Unary`, `Unimplemented` |
| `STREAM_TYPE_CLIENT_STREAM` | `ClientStream` |
| `STREAM_TYPE_SERVER_STREAM` | `ServerStream` |
| `STREAM_TYPE_HALF_DUPLEX_BIDI_STREAM` | `BidiStream` (send all, then receive all) |
| `STREAM_TYPE_FULL_DUPLEX_BIDI_STREAM` | `BidiStream` (interleaved send/receive) |

## ClientCompatRequest

Key fields the client must handle:

| Field | Type | Description |
|---|---|---|
| `test_name` | string | Test case identifier (echo back in response) |
| `host` / `port` | string / uint32 | Reference server address |
| `protocol` | enum | Will be `PROTOCOL_GRPC` for our config |
| `codec` | enum | `CODEC_PROTO` (binary) or `CODEC_JSON` |
| `compression` | enum | `COMPRESSION_IDENTITY` or `COMPRESSION_GZIP` |
| `http_version` | enum | Will be `HTTP_VERSION_2` |
| `service` | string | Default: `connectrpc.conformance.v1.ConformanceService` |
| `method` | string | `Unary`, `ServerStream`, `ClientStream`, `BidiStream`, `Unimplemented` |
| `stream_type` | enum | Determines call pattern |
| `request_headers` | repeated Header | Custom metadata to send |
| `request_messages` | repeated Any | Wrapped request protos |
| `timeout_ms` | uint32 | RPC deadline (maps to `grpc-timeout` header) |
| `request_delay_ms` | uint32 | Delay between stream sends |
| `cancel` | Cancel | Cancellation instructions |

### Cancel Timing

The `cancel` field has a `cancel_timing` oneof:

- `before_close_send` — Cancel instead of closing the send side (client/bidi streams only).
- `after_close_send_ms` — Wait N ms after close-send, then cancel (all stream types).
- `after_num_responses` — Cancel after receiving N responses (server/bidi streams only).

If `cancel` is present but no timing field is set, cancel immediately after
close-send.

## ClientCompatResponse

```
ClientCompatResponse {
  test_name: string                  // Echo from request
  result: oneof {
    response: ClientResponseResult   // Normal result (even if RPC errored)
    error: ClientErrorResult         // Infrastructure/setup error only
  }
}

ClientResponseResult {
  response_headers: repeated Header
  payloads: repeated ConformancePayload
  error: Error                       // gRPC status error (code + message + details)
  response_trailers: repeated Header
  num_unsent_requests: int32         // For streams that error mid-send
}
```

**Key distinction:** `ClientErrorResult` is for infrastructure errors (cannot
create connection, unsupported protocol, etc.). `ClientResponseResult.error` is
for RPC-level errors (the gRPC status returned by the server). Even when an RPC
returns an error, include any available headers and trailers in the response.

## Configuration

### Client Config File

The config YAML declares what features the client supports. The runner uses
this to filter applicable test cases.

For our Perl gRPC client (`conformance/grpc-client-config.yaml`):

```yaml
features:
  versions:
    - HTTP_VERSION_2
  protocols:
    - PROTOCOL_GRPC
  codecs:
    - CODEC_PROTO
  compressions:
    - COMPRESSION_IDENTITY
  supportsTls: false
  supportsConnectGet: false
  supportsTlsClientCerts: false
  supportsMessageReceiveLimit: false
```

This matches the reference gRPC client config from the ConnectRPC repository.
Features can be expanded as the implementation matures (e.g., adding
`COMPRESSION_GZIP`, `CODEC_JSON`).

### Known Failing Tests

The file `conformance/grpc-client-known-failing.txt` lists test name patterns
for tests that are expected to fail. Patterns support glob syntax. The runner
requires these tests to fail — if a "known failing" test passes, the run fails
(ensuring the list stays up to date).

For reference, the grpc-go reference client has 4 known failures, all related
to cardinality violation handling:

```
**/unary/multiple-responses
**/unary/ok-but-no-response
**/client-stream/multiple-responses
**/client-stream/ok-but-no-response
```

## What the Perl Client Does

The conformance client (`script/perl-grpc-conformance-client`) is a
long-running Perl process that:

1. **Loads** generated types from `$PROTOBUF_PP_GENDIR` (set by the wrapper
   script), falling back to `../lib`.

2. **Reads** 4-byte BE length prefix + protobuf `ClientCompatRequest` from
   stdin in a loop.

3. For each request, **establishes an HTTP/2 connection** to `host:port` and
   **makes the gRPC call** specified by `service`, `method`, and `stream_type`.

4. **Collects the result**: response headers, response payloads (as
   `ConformancePayload` messages), response trailers, and any gRPC error
   (status code, message, error details from `grpc-status-details-bin`).

5. **Writes** a 4-byte BE length prefix + protobuf `ClientCompatResponse`
   to stdout.

6. **Exits cleanly** when stdin reaches EOF or SIGTERM is received.

### gRPC Protocol Requirements

The client's HTTP/2 requests must follow the gRPC wire protocol:

| Aspect | Details |
|---|---|
| HTTP method | POST |
| Path | `/{service}/{method}` (e.g., `/connectrpc.conformance.v1.ConformanceService/Unary`) |
| Content-Type | `application/grpc+proto` (or `application/grpc+json` for JSON codec) |
| TE header | `trailers` |
| Timeout | `grpc-timeout` header (e.g., `500m` for 500ms) |
| Request metadata | Custom headers from `request_headers` (binary `-bin` suffixed headers are base64-encoded) |
| Message framing | 5-byte prefix per message: 1 byte flags (0x00 = uncompressed, 0x01 = compressed) + 4 byte BE length |
| Response status | `grpc-status` trailer (0 = OK) |
| Error message | `grpc-message` trailer (percent-encoded) |
| Error details | `grpc-status-details-bin` trailer (base64-encoded `google.rpc.Status` proto) |

### google.protobuf.Any Handling

Request messages in `ClientCompatRequest.request_messages` are wrapped in
`google.protobuf.Any`. The client must:

1. Read the `type_url` (e.g., `type.googleapis.com/connectrpc.conformance.v1.UnaryRequest`).
2. Extract the type name after the last `/`.
3. Decode the `value` bytes using the corresponding message descriptor.

### Error Mapping

gRPC status codes map directly to the conformance `Code` enum:

| gRPC Status | Code Enum | Value |
|---|---|---|
| 0 (OK) | — | No error |
| 1 (CANCELLED) | CODE_CANCELED | 1 |
| 2 (UNKNOWN) | CODE_UNKNOWN | 2 |
| 3 (INVALID_ARGUMENT) | CODE_INVALID_ARGUMENT | 3 |
| 4 (DEADLINE_EXCEEDED) | CODE_DEADLINE_EXCEEDED | 4 |
| 5 (NOT_FOUND) | CODE_NOT_FOUND | 5 |
| ... | ... | ... |
| 16 (UNAUTHENTICATED) | CODE_UNAUTHENTICATED | 16 |

The numeric values are identical — no translation needed.

## Test Suites

Test cases are defined in YAML files under `testsuites/` in the ConnectRPC
repository. Suites relevant to gRPC client testing:

| Suite | Description |
|---|---|
| `basic.yaml` | Success cases across all stream types |
| `errors.yaml` | All 16 error codes for unary and streaming |
| `timeouts.yaml` | Deadline/timeout propagation |
| `client_cancellation.yaml` | Client-initiated RPC cancellation |
| `duplicate_metadata.yaml` | Duplicate header keys |
| `server_message_size.yaml` | Large message handling |
| `grpc_client_empty.yaml` | Empty responses in gRPC |
| `grpc_client_trailers.yaml` | Trailer handling for gRPC |
| `grpc_client_unexpected.yaml` | Unexpected/malformed gRPC responses |
| `grpc_client_proto_subformat.yaml` | Proto codec specifics for gRPC |

Suites prefixed with `connect_*` or `grpc_web_*` are filtered out by the
config (we only declare `PROTOCOL_GRPC`).

## Running the Tests

### Basic Run

```bash
script/grpc-conformance-test --connectrpc-root /path/to/connectrpc-conformance
```

The wrapper script generates types into a temp directory and runs
`connectconformance` with the correct flags. Extra arguments are passed
through to the runner:

```bash
# Run specific tests
script/grpc-conformance-test --connectrpc-root /path/to/conformance \
  --run "Basic/**/unary/*"

# Verbose output
script/grpc-conformance-test --connectrpc-root /path/to/conformance -v
```

### Environment Variable

Instead of `--connectrpc-root`, you can set `$CONNECTRPC_ROOT`:

```bash
export CONNECTRPC_ROOT=/path/to/connectrpc-conformance
script/grpc-conformance-test
```

## Prerequisites

### ConnectRPC Conformance Source Tree

The wrapper script needs access to the connectrpc-conformance source tree
(for proto include files and the `connectconformance` binary):

```bash
git clone https://github.com/connectrpc/conformance.git
cd conformance
go build -o .tmp/bin/connectconformance ./cmd/connectconformance
```

The wrapper script looks for the binary at
`$CONNECTRPC_ROOT/.tmp/bin/connectconformance`, then falls back to `$PATH`.

### `protoc` Compiler

The `protoc` compiler must be on `$PATH`. It is used by the wrapper script
to generate Perl types into a temp directory before each run.

## Test Matrix

With the minimal gRPC config (HTTP/2, gRPC protocol, proto codec, identity
compression, no TLS), the test matrix is:

- 1 HTTP version x 1 protocol x 1 codec x 1 compression = 1 config permutation
- Applied across ~10 relevant test suites

Total: **211 test cases**, all passing.

Adding gzip compression doubles the permutations. Adding JSON codec doubles
again. The matrix grows with each supported feature.

## Reference Implementation

The grpc-go reference client in the ConnectRPC repository demonstrates the
expected behavior:

- **Main loop**: `internal/app/grpcclient/client.go` — reads requests, spawns
  goroutines, writes responses.
- **RPC dispatch**: `internal/app/grpcclient/impl.go` — all 6 method
  implementations with cancellation, timeout, metadata, and error handling.

Key patterns to follow from the reference:

1. **Connection per request** — The reference creates a new gRPC connection
   for each `ClientCompatRequest` (though production clients would reuse).
2. **Metadata handling** — Request headers are sent as gRPC metadata.
   Response headers and trailers are captured separately.
3. **Error conversion** — gRPC status errors are converted to the conformance
   `Error` proto with code, message, and details (from `grpc-status-details-bin`).
4. **Stream lifecycle** — For client/bidi streams, sends happen in order with
   delays, then close-send, then read remaining responses.

## Data Flow Example

A single unary test iteration:

```
1. Runner writes to client stdin:
   [4-byte BE length][protobuf ClientCompatRequest]
     test_name: "Basic/HTTPVersion:2/Protocol:GRPC/Codec:Proto/Compression:Identity/unary/success"
     host: "127.0.0.1", port: 38291
     protocol: PROTOCOL_GRPC, codec: CODEC_PROTO
     method: "Unary", stream_type: STREAM_TYPE_UNARY
     request_messages: [Any{UnaryRequest{response_definition: ...}}]

2. Client decodes the ClientCompatRequest.

3. Client opens HTTP/2 connection to 127.0.0.1:38291.

4. Client sends HTTP/2 POST to:
     /connectrpc.conformance.v1.ConformanceService/Unary
   With headers:
     content-type: application/grpc+proto
     te: trailers
     x-conformance-test: Value1, Value2
   Body: [5-byte gRPC frame][protobuf UnaryRequest]

5. Server responds with:
   Headers: x-custom-header: foo
   Body: [5-byte gRPC frame][protobuf UnaryResponse]
   Trailers: grpc-status: 0, x-custom-trailer: bing

6. Client builds ClientResponseResult:
     response_headers: [{name: "x-custom-header", value: ["foo"]}]
     payloads: [ConformancePayload from UnaryResponse]
     response_trailers: [{name: "x-custom-trailer", value: ["bing"]}]

7. Client writes to stdout:
   [4-byte BE length][protobuf ClientCompatResponse]

8. Runner compares against expected result, records pass/fail.
```

## Debugging

The conformance client redirects STDERR to
`/tmp/perl-grpc-conformance-client.log`. Any `warn` or diagnostic output goes
there instead of interfering with the binary pipe protocol on stdout.

To debug a specific test failure, check the log after a run:

```bash
script/grpc-conformance-test --connectrpc-root /path/to/conformance
cat /tmp/perl-grpc-conformance-client.log
```

The runner itself provides useful output via extra args:

- **Verbose mode** (`-v`) shows each test name and pass/fail status.
- **Trace mode** (`--trace`) dumps HTTP/2 frames for debugging wire-level issues.
- **Specific test runs** (`--run "pattern"`) narrow down to a single failing
  test for focused debugging.
