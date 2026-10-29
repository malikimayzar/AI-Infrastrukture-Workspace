# ADR-003: PDF Export Dependency for Audit Reports (P2)

## Status

Proposed — pending owner approval before implementation.

## Context

Vertical 1 P1 deferred `export.pdf` because `mcp-gateway/go.mod` has no PDF
library. P2 requires a decision on how to render audit reports to PDF without
violating AGENTS.md §4.2 (no unapproved dependency pin changes) and §3
(repository ownership: gateway owns rendering, not a new service).

Current state: `export.md` and `export.json` are rendered in-process from
persisted rows (`buildReportMarkdown` in `cmd/server/reports.go`). PDF is the
only remaining export format in the P0/P1 contract.

## Evaluated Options

### Option 1: Go library (gofpdf / maroto / unipdf)
- **Pros**: in-process, no new service, fits gateway ownership, fast.
- **Cons**: new dependency pin; layout code in Go; limited styling.
- **Candidate**: `github.com/jung-kurt/gofpdf` (MIT) or `github.com/unidoc/unipdf` (commercial license).

### Option 2: Headless Chromium via `chromedp`
- **Pros**: reuses existing `export.md`→HTML→PDF, rich styling.
- **Cons**: heavy binary (~150 MB), new service or sidecar, violates W-2 (no new service in P0; P2 may allow).

### Option 3: Python sidecar (reportlab / weasyprint)
- **Pros**: rich layout, familiar stack.
- **Cons**: new service in topology (violates W-2 spirit), cross-repo ownership
  boundary (gateway must not own Python rendering; new repo/service needed).

## Decision (proposed)

Option 1 with `gofpdf` (MIT, no license cost) as the smallest in-process change.
Add pin to `go.mod` only after owner approval; ADR status → Accepted.

## Consequences

- New dependency pin in `go.mod` (requires approval per AGENTS.md §4.2).
- `handleExportReport` gains `.pdf` suffix branch rendering via gofpdf.
- No topology change; no new service (W-2 preserved).
- Fallback: if PDF render fails, return 500 with generic message (consistent
  with existing error handling in reports.go).

## Open

- Owner approval of dependency pin.
- Confirmation that gofpdf license (MIT) is acceptable.
- Whether to include span attribution tables in PDF (layout complexity).
