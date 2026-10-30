# MCP stdio bridge — design

> **Date:** 2026-10-25 (revised)
> **Status:** Proposed — awaiting approval
> **Scope:** Phase 3 — MCP client interoperability
> **Repo:** `mcp-gateway`
> **Supersedes:** earlier draft that excluded legacy `initialize`

## Intent

Claude Desktop and similar clients launch local MCP servers as subprocesses and
speak newline-delimited JSON-RPC over stdio. The gateway currently exposes only
HTTP `POST /mcp` using the 2026-07-28 per-request model, and it intentionally
rejects the legacy `initialize` handshake with `-32601`.

This change adds `cmd/mcp-stdio`, a compatibility bridge that lets both modern
and legacy stdio clients use the existing HTTP gateway without duplicating tool
execution logic. The HTTP core stays pure 2026-07-28; the bridge owns framing,
header derivation, and the legacy handshake shim.

The docs that motivated this shape:

- `docs/mcp-integration-guide.md` — current HTTP contract and 2026-07-28 rules.
- `docs/superpowers/plans/2026-10-23-phase-2-production-gates.md` — Phase 3
  roadmap: stdio + Streamable HTTP, SSE is legacy, SDK needs Go 1.25.
- `docs/product-strategy.md` — MCP tools and Claude Desktop/Cursor are the
  primary commercialization path.
- `docs/superpowers/plans/2026-10-24-cross-repo-remediation.md` — auth is
  explicitly deferred to P3.

## Goals

- Add `cmd/mcp-stdio`, a single binary that:
  - reads one JSON-RPC 2.0 message per line from stdin;
  - forwards each non-local request to `POST <gateway>/mcp`;
  - writes exactly one JSON-RPC response per request to stdout;
  - writes nothing to stdout for notifications and `202 Accepted`;
  - writes all diagnostics to stderr only.
- Support two client modes:
  - **Modern (2026-07-28):** pass the message through unchanged; derive
    `MCP-Protocol-Version`, `Mcp-Method`, and `Mcp-Name` from the body.
  - **Legacy handshake:** answer `initialize` locally, consume
    `notifications/initialized`, capture the client's capabilities, and inject
    the required `params._meta` into subsequent forwarded requests.
- Preserve gateway JSON-RPC errors unchanged, including `data.supported` for
  `-32022`, so clients can retry with a supported version.
- Convert transport failures (connection refused, timeout, empty/non-JSON
  response, oversized response) into `-32603` with the original request `id`.
- Generate an `X-Request-ID` per forwarded message and log it to stderr for
  correlation with gateway logs.
- Configuration:
  - `--url` (default `http://localhost:8090/mcp`);
  - `MCP_GATEWAY_URL` environment variable as fallback;
  - `--timeout` (default `5m`).
- Exit `0` on stdin EOF or SIGINT/SIGTERM. Exit non-zero only for
  startup/configuration errors.
- Enforce a 1 MiB request line limit and an 8 MiB gateway response limit.

## Non-goals

- **No SSE streaming.** Per the Phase 3 roadmap, SSE is a legacy transport and
  is not a target for this revision. JSON responses are conformant for
  2026-07-28.
- **No authentication, TLS, or rate limiting.** Auth was explicitly deferred to
  P3 on 2026-10-24. The bridge is a local process; `/mcp` must be treated as
  localhost-only and must not be exposed publicly until auth lands.
- **No SDK conformance gate in v1.** The official Go SDK requires Go 1.25; the
  gateway is Go 1.22. v1 uses the existing handler plus transcript tests. SDK
  conformance is a follow-up after a toolchain upgrade.
- **No native stdio server.** Refactoring `internal/mcp` to run directly over
  stdin/stdout duplicates the protocol path and wiring.
- **No concurrent request pipelining.** Messages are processed sequentially. A
  long tool call delays subsequent messages; the HTTP timeout bounds the wait.
- **No cancellation propagation beyond forwarding
  `notifications/cancelled`.** In-flight HTTP requests are not aborted.
- **No translation of resources, prompts, sampling, or older protocol
  semantics.** The bridge advertises tools only. Other methods are forwarded and
  the gateway's `-32601` is passed through.
- **No emulation of older protocol revisions.** A legacy client that sends
  `initialize` is accepted, but the bridge advertises `2026-07-28`. If the
  client cannot use that revision, it will disconnect; capture the transcript
  and add translation as a separate, evidence-driven change.

The auth/rate-limit and SDK-conformance deferrals deliberately deviate from the
Phase 2 plan's Phase 3 gate. The newer 2026-10-24 decision and the Go 1.22
constraint take precedence; record the deviation in the Phase 3 acceptance doc.

## Constraints

- Go 1.22, matching `mcp-gateway/go.mod` and `Dockerfile`. Do not add the
  official MCP SDK in this change.
- Reuse `internal/mcp` constants and error constructors. Do not duplicate tool
  execution, registry, or backend logic.
- The bridge is a local process. It must not log request bodies, tool arguments,
  or secrets.
- The gateway must already be running. The bridge does not start or embed it.
- The gateway's `Origin` validation passes because the bridge does not send an
  `Origin` header.

## Decision log

| Decision | Choice | Source |
|---|---|---|
| Transport | Streamable HTTP + stdio bridge | Phase 2 plan; `mcp-integration-guide.md` |
| Protocol | 2026-07-28 per-request model | `mcp-integration-guide.md`; `internal/mcp` |
| Legacy `initialize` | Bridge-local shim | `PROJECT_GOALS.md` Phase 3; product strategy |
| SSE | Legacy / deferred | Phase 2 plan line 43 |
| Auth + rate limit | Deferred to P3 | Cross-repo decision 2026-10-24 |
| SDK conformance | Deferred; Go 1.22 vs SDK 1.25 | Phase 2 plan line 44 |
| Native stdio server | Rejected | Earlier approach selection |

## Approaches considered

1. **Pure 2026-07-28 bridge.** Smallest change, but legacy clients that send
   `initialize` receive `-32601` and cannot connect. It also leaves the
   `initialize` checkbox in `PROJECT_GOALS.md` unresolved.
2. **Dual-mode bridge (chosen).** The HTTP core stays pure 2026-07-28; the
   bridge answers the legacy handshake locally and translates subsequent
   requests. One protocol implementation remains in the gateway; compatibility
   lives in one testable process.
3. **Native stdio server.** Refactor `internal/mcp` to be transport-agnostic and
   run it over stdin/stdout. Lower latency, but a larger refactor with duplicated
   wiring, config, and two code paths to test.
4. **Interop-first.** Build the conformance harness and defer the adapter.
   Avoids building the wrong compatibility layer, but leaves Claude Desktop and
   Cursor unable to connect.

Option 2 is chosen because it satisfies the two open Phase 3 checkboxes —
stdio adapter and external-client interoperability — without regressing the
tested HTTP core.

## Design

### Process loop

`Run(ctx, in, out, errOut, cfg)` is the testable core; `main` wires
`os.Stdin`, `os.Stdout`, `os.Stderr`, flags, and signals.

1. Read a line from stdin, trimming a trailing `\r\n`. Skip empty/whitespace-only
   lines. Enforce the 1 MiB limit; on overflow, discard the rest of the line,
   emit `-32600` with `id: null`, and continue.
2. Parse the JSON-RPC envelope:
   - invalid JSON → `-32700` with `id: null`;
   - missing/invalid `jsonrpc` or `method` → `-32600` with the request `id` when
     available;
   - `id: null` → `-32600`;
   - no `id` member → notification.
3. If the message is `initialize`, handle it locally (see below) and do not call
   the gateway. An `initialize` without an `id` is logged and ignored.
4. If the message is `notifications/initialized`, consume it locally and write
   nothing to stdout. If it carries an `id`, return `-32600`.
5. Otherwise build the HTTP request:
   - body is the message bytes, unchanged for modern clients;
   - for an active legacy session, inject the required `params._meta` fields;
   - `Content-Type: application/json`, `Accept: application/json`;
   - headers derived as described below;
   - generated `X-Request-ID`.
6. Send the request with the configured timeout and a bounded response reader.
7. For a notification:
   - `2xx`/`202` is success; write nothing to stdout;
   - transport or HTTP failure is logged to stderr; write nothing to stdout.
8. For a request:
   - if the response body is a valid JSON-RPC object, compact it and write one
     line to stdout;
   - if the body is empty or not JSON, synthesize `-32603`;
   - if the HTTP request failed, synthesize `-32603` with a stable message.
9. Continue until stdin EOF or context cancellation, then return `nil`.

### Legacy handshake shim

The shim removes the need for a client to speak the per-request model; it does
not emulate older protocol revisions.

**`initialize` request** (must have an `id`):

An `initialize` without an `id` is not a valid handshake request: log a warning
and ignore it; do not forward it.

- Capture `params.capabilities` (object, default `{}`) and
  `params.clientInfo` (object, optional).
- Log the client's requested `params.protocolVersion` at info level for
  diagnostics.
- Respond locally; do not call the gateway:

```json
{
  "jsonrpc": "2.0",
  "id": "<request id>",
  "result": {
    "protocolVersion": "2026-07-28",
    "capabilities": {
      "tools": {
        "listChanged": false
      }
    },
    "serverInfo": {
      "name": "mcp-gateway-stdio",
      "version": "1.0.0"
    }
  }
}
```

- A second `initialize` resets the captured state.

**`notifications/initialized`:**

- Consume locally; write nothing to stdout.
- If it carries an `id`, return `-32600` (`initialized` must be a notification).
- If no `initialize` preceded it, log a warning and continue.

**Subsequent requests while a legacy session is active:**

- Merge into `params._meta`:
  - `io.modelcontextprotocol/protocolVersion`: `"2026-07-28"`;
  - `io.modelcontextprotocol/clientCapabilities`: the captured capabilities or
    `{}`;
  - `io.modelcontextprotocol/clientInfo`: the captured client info, if present.
- Preserve unrelated `_meta` keys; the bridge values take precedence for the
  required fields.
- Derive headers from the translated body.

**Modern clients:**

- No local state; the body is forwarded unchanged.
- If `params._meta` is missing, the bridge does not invent it; the gateway
  returns `-32602`.

### Header derivation

| Header | Modern | Legacy session |
|---|---|---|
| `MCP-Protocol-Version` | `params._meta["io.modelcontextprotocol/protocolVersion"]` | `2026-07-28` |
| `Mcp-Method` | `method` | `method` |
| `Mcp-Name` | `params.name` for `tools/call` | `params.name` for `tools/call` |
| `X-Request-ID` | generated | generated |
| `Content-Type` | `application/json` | `application/json` |
| `Accept` | `application/json` | `application/json` |

If a required value is absent, the header is omitted and the gateway returns the
appropriate JSON-RPC error. The bridge does not guess.

### Error mapping

| Condition | stdout |
|---|---|
| Gateway returns a JSON-RPC error (400/404/500) | Pass through unchanged |
| Gateway returns a success result | Pass through unchanged |
| Connection refused | `-32603`, message `gateway unreachable`, `data.cause` |
| Timeout | `-32603`, message `gateway timeout`, `data.cause` |
| Empty or non-JSON gateway response | `-32603`, message `invalid gateway response`, `data.http_status` |
| Gateway response over 8 MiB | `-32603`, message `gateway response too large` |
| Invalid JSON on stdin | `-32700`, `id: null` |
| Oversized line | `-32600`, `id: null`, message `request exceeds 1 MiB limit` |
| Invalid JSON-RPC envelope | `-32600`, request `id` when available |
| Notification transport failure | No stdout; log to stderr |
| Local `initialize` marshal failure | `-32603` with the request `id` |

No error path writes logs, stack traces, or partial JSON to stdout.

### Code structure

- `cmd/mcp-stdio/main.go`: flags, URL validation, signal context, `Run`, exit
  codes.
- `internal/mcpstdio/`:
  - `Config` (`URL`, `Timeout`);
  - `Run(ctx, in, out, errOut, cfg)`;
  - `Envelope` with `ID json.RawMessage`, `Method`, `Params`, `JSONRPC`;
  - `parseEnvelope`, `readLine`, `deriveHeaders`, `legacyState`,
    `translateRequest`, `mapTransportError`, `writeResponse`.
- `internal/mcp/server.go`: add a small exported `RegisterTool(tool Tool)`
  method so tests outside the package can register a stub tool. No behavior
  change; `RegisterGatewayTools` may use it too.
- Reuse `mcp.ProtocolVersion`, `mcp.ParseError`, `mcp.InvalidRequest`,
  `mcp.InternalError`, `mcp.UnsupportedProtocolVersion`, and the existing error
  constructors.
- No tool execution, registry, or backend code in the bridge.

### Tests

**Unit**

- Envelope parsing: request, notification, `id: null`, missing `method`, invalid
  JSON, CRLF, empty line.
- Header derivation for `server/discover`, `tools/list`, `tools/call`, and a
  legacy translated request.
- Legacy state: capture capabilities, inject `_meta`, preserve unrelated keys,
  reset on a second `initialize`.
- Line reader: 1 MiB boundary, oversized line discard, partial line at EOF.
- Error mapping: connection refused, timeout, empty body, non-JSON body,
  oversized body.

**Integration with `httptest.Server` + `mcp.NewHandler` + a stub tool registered
through `Server.RegisterTool`**

- Modern transcript: `server/discover` → `tools/list` → `tools/call`; one
  response per request; headers captured by middleware match the body.
- Legacy transcript: `initialize` → `notifications/initialized` →
  `tools/list` → `tools/call`; `initialize` and `initialized` produce no HTTP
  POST; `tools/list` and `tools/call` carry injected `_meta` and headers; stdout
  contains exactly the initialize and tool responses.
- Notification: `notifications/cancelled` → `202`, no stdout, server sees a
  POST.
- Error pass-through: unsupported version (`-32022` with `data.supported`) and
  unknown tool (`-32602`).
- Tool error: gateway returns `result.isError: true`; the bridge passes it
  through unchanged.
- Transport failure: closed server → `-32603` with the original `id`.
- Invalid JSON, missing `method`, and an oversized line do not stop the process;
  a following valid request still succeeds.
- EOF exits cleanly; every stdout line parses as JSON; stderr may contain logs.

**Commands**

```bash
cd mcp-gateway
go test ./... -race
go vet ./...
go build ./...
```

**Manual interop checklist**

- Claude Desktop: configure the bridge, restart, verify the three tools appear,
  call each tool, and confirm stderr logs with request IDs.
- Cursor: same checklist via its MCP stdio configuration.
- If a client cannot connect, capture its logs/transcript and add a failing test
  before changing code. Record the result as `verified`, `blocked`, or
  `not available`; do not claim interop without evidence.

## Documentation

| File | Change | Timing |
|---|---|---|
| `docs/mcp-integration-guide.md` | Add a stdio bridge section; document modern and legacy flows, config, and limitations; remove the stale “Phase 2” label | With implementation |
| `docs/mcp-claude-desktop-example.md` | Rewrite for the bridge; remove `initialize` + top-level `_meta` examples and the fake Node one-liner; add Claude Desktop and Cursor configs | Before/with implementation |
| `docs/mcp-transport-decision.md` | Rewrite to 2026-07-28 Streamable HTTP + stdio bridge; mark SSE legacy/deferred | Before/with implementation |
| `PROJECT_GOALS.md` | Fix the status line; replace the stale `initialize` checkbox with `server/discover` + per-request `_meta`; add the bridge legacy shim; mark stdio/interop in progress; mark SSE legacy/deferred | After design approval, before implementation |
| `mcp-gateway/README.md` | Replace “MCP interoperability is not implemented yet” with the actual HTTP + stdio surface | After interop evidence |
| `mcp-gateway/PROJECT_GOALS.md` | Replace the “describe as HTTP until MCP is implemented” line | After interop evidence |
| `mcp-gateway/PROJECT_CONTEXT.md` | Record the verified MCP surface | After interop evidence |
| `mcp-gateway/IMPLEMENTATION_TODO.md` | Check the MCP transport/interop item | After interop evidence |
| `docs/acceptance/phase-3-mcp-interop.md` | New acceptance record: baseline commits, commands, transcripts, results, limitations | After interop evidence |

Notes:

- `PROJECT_GOALS.md` currently has unrelated uncommitted changes. Patch only the
  Phase 3 lines and show the diff before committing.
- `docs/mcp-claude-desktop-example.md` and `docs/mcp-transport-decision.md` are
  currently untracked. Add them explicitly; never use `git add -A`.
- Do not update the submodule README/goals until the interop evidence exists.

## Rollout

Build:

```bash
cd mcp-gateway
go build -o mcp-stdio ./cmd/mcp-stdio
```

Claude Desktop configuration:

```json
{
  "mcpServers": {
    "scientific-audit": {
      "command": "/absolute/path/to/mcp-stdio",
      "args": ["--url", "http://localhost:8090/mcp"]
    }
  }
}
```

Cursor uses the same command/args in its MCP stdio configuration.

The gateway must be running (`make up` in Mode A, or the per-project Compose in
Mode B). Manual verification:

```bash
# Modern flow
printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"server/discover","params":{"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28","io.modelcontextprotocol/clientCapabilities":{}}}}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28","io.modelcontextprotocol/clientCapabilities":{}}}}' \
  | ./mcp-stdio

# Legacy flow
printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"manual","version":"1"}}}' \
  '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' \
  | ./mcp-stdio
```

Expected: one JSON-RPC response per request on stdout; `initialized` produces no
output; logs go to stderr.

## Acceptance criteria

- Modern transcript passes with one response per request and no stdout logs.
- Legacy transcript passes: `initialize` is local, `initialized` is consumed,
  and subsequent requests carry injected `_meta` and headers.
- Notification produces `202` and no stdout.
- Gateway errors pass through, including `-32022` with `data.supported` and
  tool-level `isError: true`.
- Transport failures produce `-32603` with the original `id`.
- Invalid JSON, missing `method`, and oversized lines keep the process serving.
- EOF exits `0`; stdout contains only JSON-RPC lines.
- `go test ./... -race`, `go vet ./...`, and `go build ./...` pass.
- Claude Desktop/Cursor interop is recorded as verified, blocked, or not
  available; no unverified claim is made.
- `make check-secrets` remains clean.

## Risks

- **Legacy version rejection:** the bridge advertises 2026-07-28. A client that
  requires an older revision will disconnect. Capture the transcript before
  adding translation.
- **Capability drift:** the local `initialize` response hardcodes the tools
  capability. A test asserts the shape; update it if the gateway gains
  capabilities.
- **Sequential processing:** a long tool call blocks the next line. The HTTP
  timeout bounds the wait.
- **Gateway dependency:** the bridge is not standalone. A local `initialize`
  succeeds even if the gateway is down; the first forwarded request then fails
  with `-32603`.
- **No auth:** `/mcp` must be treated as localhost-only until P3-1 lands.
- **Response size:** the 8 MiB cap may reject unusually large tool results;
  adjust only with evidence.
- **SDK conformance deferred:** the official SDK's Go 1.25 requirement is a
  follow-up, not a v1 blocker.
- **Docs drift:** the acceptance doc and the documentation table above are the
  guard against stale claims.

## Follow-ups (not this change)

- Upgrade the gateway toolchain to Go 1.25 and add official SDK client
  conformance tests.
- Add auth and rate limiting (P3-1) before exposing `/mcp` beyond localhost.
- Add SSE only if a client requires streaming; treat it as a separate transport
  decision.
- Add translation for older protocol revisions if a real client transcript
  requires it.
- Add resources/prompts/sampling only when the gateway actually exposes them.
