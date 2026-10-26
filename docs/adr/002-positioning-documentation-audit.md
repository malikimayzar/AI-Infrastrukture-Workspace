# ADR-002: Position as Clinical Documentation Audit, Not Clinical Decision Support

## Status

Proposed — 2026-10-25

## Context

The workspace was built as a *Scientific Claim & Prior-Art Auditor*: ingest papers,
extract claims, retrieve evidence, return a verdict, and abstain when evidence is
insufficient. The core pattern is domain-agnostic:

```
claim → evidence retrieval → verdict → calibrated confidence → abstention
```

Two forces make healthcare an attractive first vertical:

1. **The pattern already exists manually.** Clinical Documentation Integrity (CDI)
   teams verify every day whether a billed diagnosis or procedure code is supported
   by the clinical note. That is claim verification with a human reference standard.
2. **The cost of unsupported claims is measurable.** Denied claims, audit findings,
   case-mix index erosion, and compliance risk are concrete, budgeted problems.

At the same time, healthcare software carries regulatory and liability exposure that
the current project has never had to handle. A careless positioning choice can turn
an administrative tool into a regulated medical device.

The decision below is about **positioning**, not architecture. The architecture
stays; the boundary changes.

## Decision

Position the healthcare offering as **administrative clinical documentation audit**,
not as clinical decision support.

Concretely:

1. The system identifies codes that are unsupported, partially supported, or
   contradicted by the documentation, and drafts physician queries for human review.
2. The system **never** suggests a diagnosis, a treatment, a dose, or a triage
   decision.
3. The system **never** changes a code, a claim, or a record autonomously.
4. The published intended use is limited to CDI and coding support
   (see `docs/healthcare/INTENDED_USE.md`).
5. Human-in-the-loop is mandatory and auditable.
6. Default deployment for identifiable data is on-premise; cloud LLM providers are
   used only for de-identified data under a data processing agreement.

## Consequences

### Positive

- Lower regulatory burden than SaMD/CDS, assuming the intended use stays
  administrative and is reviewed by legal.
- The existing architecture (retrieval, abstention, calibration, attribution) is
  directly reusable.
- The buyer is identifiable (hospital CDI/coding leadership) and the pain is
  already budgeted.
- Clinical validation is measurable against an existing human reference standard
  (coders), unlike generic "faithfulness".

### Negative

- Enterprise sales cycle is long (6–18 months) and requires a clinical champion.
- PHI handling requires on-prem deployment, DPA, and security review.
- The current default provider (Groq cloud) cannot be used for identifiable data.
- Attribution must move from chunk-level to span-level before the product is
  credible.
- Calibration must actually load at runtime; today it silently falls back.

### Neutral

- The scientific-literature use case is not abandoned; it becomes the
  de-identified, no-PHI entry point and the evaluation harness.
- MCP remains a distribution channel, not the product.

## Alternatives considered

### A. Clinical Decision Support (CDS)

Rejected. Suggesting diagnosis or treatment moves the product into SaMD territory,
requiring clinical evidence, risk classification, and likely a regulatory submission.
The project has no clinical validation capability today.

### B. Medical literature audit only (no PHI)

Viable and low-risk, but weaker commercially: the buyer is a researcher or medical
writer, willingness to pay is lower, and the space is crowded with citation checkers
that are free. It remains a useful wedge but not the primary position.

### C. Generic claim-verification API

Rejected. The market already has funded players and free citation checkers. A
generic API has no defensible edge; the domain-specific reference standard (coders)
does.

## Compliance notes

- Intended use must be reviewed against Indonesian regulations, including
  UU 27/2022 (PDP), Permenkes 24/2022 (electronic medical records), and applicable
  medical-device rules.
- This ADR does not assert that the product is exempt from regulation. It records a
  positioning decision that must be confirmed by legal/compliance.
- Any change that adds clinical recommendations requires a new ADR and regulatory
  review.

## Follow-ups

- [ ] Legal review of `INTENDED_USE.md`
- [ ] Identify clinical advisor / senior coder
- [ ] Decide pilot site and data access model
- [ ] Implement span-level attribution
- [ ] Fix calibration loading and add health check
- [ ] Separate "research" and "clinical" runtime profiles
- [ ] Build clinical validation harness
- [ ] Archive duplicate status documents; create single `STATUS.md`
