# PQ Integrity Checker

## Purpose

A background process that walks every signable row in PostgreSQL — shape by shape — and verifies cryptographic integrity. Today, signature validation happens only at write time (HTTP ingest and peer sync). If a row is corrupted after persistence (manual SQL, failed migration, disk error, logical replication glitch), no mechanism detects it. The integrity checker closes that gap.

---

## Problem

Both write pipelines — `ElectricController` (HTTP ingest) and `ShapeWriter` (peer sync) — validate `sign_b64` before persisting. But once a row lands in PostgreSQL, it is trusted unconditionally:

- Electric streams it as-is to all shape consumers.
- `chat-frontend` applies it to TanStack collections and IndexedDB without verification.
- LiveView `sync_stream_fixed` renders it without verification.

Any post-persistence corruption is invisible. The system serves malformed rows to all peers and frontends as if they were authentic.

### Threat surface

| Vector | Risk |
|--------|------|
| Manual SQL (`UPDATE`, `DELETE` + re-insert) | Bypass all validation — signature becomes invalid |
| Failed migration | Field value changed without re-signing |
| Logical replication bug | Row arrives incomplete or with wrong field values |
| Disk / filesystem corruption | Bit flip in any signed field invalidates `sign_b64` |
| Compromised peer in sync | If `ShapeWriter` validation has a bug, a bad row persists |

---

## Design

### Core: `Chat.Data.IntegrityChecker`

A module (not a GenServer — triggered, not scheduled) that iterates over shapes and validates every row.

```
IntegrityChecker.run()
  │
  ├── for each shape in Shapes.all():
  │     │
  │     ├── skip if schema does not implement Signable protocol
  │     │
  │     ├── stream all rows from Repo (batched, cursor-based)
  │     │
  │     ├── for each row:
  │     │     ├── Integrity.verify_signature(row)
  │     │     ├── validate timestamp monotonicity (optional, per-shape)
  │     │     └── collect result: :ok | {:error, shape, pk, reason}
  │     │
  │     └── yield shape summary: {shape_name, total, valid, invalid, errors}
  │
  └── return full report
```

### Shape iteration

Use `Chat.Data.Shapes.all/0` for the shape list. For each shape module:

1. Get `schema_module/0` — the Ecto schema.
2. Check that the schema implements `Chat.Data.Integrity.Signable` — skip shapes without signatures (candidates that have no `sign_b64`).
3. Stream rows via `Repo.stream/2` inside a transaction (read-only, `READ COMMITTED`) in batches of 500.
4. For each row, call `Chat.Data.Integrity.verify_signature/1`.
5. Collect failures with primary key, shape name, and error reason.

### What to check

| Check | Applies to | How |
|-------|-----------|-----|
| Signature validity | All signable rows | `Integrity.verify_signature/1` → `:ok` or `{:error, :invalid_signature}` |
| Parent existence | Rows with `sync_required_parents` | Parent row exists in DB (FK integrity) |
| Timestamp sanity | Rows with `owner_timestamp` | Non-null, positive integer |

Signature verification is the primary check — it catches any field mutation. Parent and timestamp checks are secondary diagnostics.

### Report format

```elixir
%IntegrityChecker.Report{
  started_at: DateTime.t(),
  finished_at: DateTime.t(),
  shapes: [
    %{
      shape: :user_card,
      total: 142,
      valid: 140,
      invalid: 2,
      errors: [
        %{pk: %{user_hash: "u_abc..."}, reason: :invalid_signature},
        %{pk: %{user_hash: "u_def..."}, reason: :invalid_signature}
      ]
    },
    ...
  ]
}
```

### Triggering

The checker is not a daemon. It runs on demand via:

1. **IEx** — `Chat.Data.IntegrityChecker.run()` for the full sweep, or `Chat.Data.IntegrityChecker.check_shape(:user_card)` for a single shape.
2. **Admin UI** — a button on the Electric admin page (`/electric/admin` or equivalent) that kicks off a check and displays results.
3. **Platform boot** — optionally, after `BootSupervisor` finishes the drive startup sequence, run an integrity sweep and log a summary. Gated by a config flag (default: off) since the sweep may be slow on large databases.

### Performance considerations

- **Batched streaming** — `Repo.stream` with `:max_rows` to avoid loading entire tables into memory.
- **Read-only transaction** — no locks held beyond the cursor.
- **Per-shape isolation** — each shape check is independent; a failure in one does not abort others.
- **Optional concurrency** — shapes without FK dependencies between them can be checked in parallel via `Task.async_stream`. Start sequential; parallelize if performance demands it.
- **Row count estimate** — before streaming, `SELECT reltuples FROM pg_class WHERE relname = '<table>'` gives a fast approximate count for progress reporting.

### What it does NOT do

- **Quarantine or delete invalid rows.** The checker reports — it does not modify data. A separate remediation step (manual or automated) decides what to do with flagged rows.
- **Real-time filtering.** This is a batch audit, not a read-path filter. Adding client-side signature verification to the frontend or LiveView display path is a separate concern.
- **Version table checks.** Version rows (`user_storage_versions`, `dialog_message_versions`) are historical snapshots. Checking them is valuable but lower priority — start with current rows.

---

## API

```elixir
# Full sweep — all shapes
{:ok, report} = Chat.Data.IntegrityChecker.run()

# Single shape
{:ok, shape_report} = Chat.Data.IntegrityChecker.check_shape(:user_card)

# With options
{:ok, report} = Chat.Data.IntegrityChecker.run(
  shapes: [:user_card, :user_storage],     # subset
  batch_size: 1000,                         # rows per batch (default: 500)
  on_invalid: fn shape, pk, reason -> ... end  # callback per invalid row
)
```

---

## Implementation plan

### Phase 1 — Core checker

1. `Chat.Data.IntegrityChecker` module with `run/0`, `run/1`, `check_shape/1`, `check_shape/2`.
2. Iterate `Shapes.all/0`, stream rows, call `Integrity.verify_signature/1`.
3. Return structured report.
4. Tests: seed valid and deliberately-malformed rows, assert the checker catches them.

### Phase 2 — Admin UI

1. Add a "Run Integrity Check" action to the Electric admin/sandbox area.
2. Display results: per-shape table with totals, expandable error list with primary keys.
3. Progress indication for long-running checks (PubSub or LiveView async assign).

### Phase 3 — Platform integration

1. Optional post-boot sweep in `BootSupervisor` (gated by config).
2. Log summary at `:info` level; log individual failures at `:warning`.
3. Broadcast result via PubSub for admin dashboard consumption.

### Phase 4 (future) — Remediation

Out of scope for this req, but the natural follow-up:
- Quarantine table for invalid rows (move out of main table, keep for forensics).
- Re-fetch from peer: if a peer has the same row with a valid signature, replace the local copy.
- Version table auditing.

---

## Relationship to existing invariants

- **[02_integrity.md](../invariants/02_integrity.md)** — defines the signature scheme this checker verifies.
- **[electric_shape_behaviours.done.md](electric_shape_behaviours.done.md)** — defines the shape registry and `Signable` protocol implementations this checker iterates.
- **[01_proof_of_possession.md](../invariants/01_proof_of_possession.md)** — PoP guards write-time; this checker guards at-rest.

---

## Status

Proposed.

---

## Open questions

1. **Should invalid rows be excluded from Electric shape streams?** A PostgreSQL trigger or view could filter rows where `sign_b64` verification fails, but this adds per-row compute cost to every shape read. Alternatively, a materialized "invalid row" table could be maintained and excluded via `WHERE NOT EXISTS`. Trade-off: read-path safety vs. read-path performance.

2. **Should the frontend verify signatures on read?** `enigma.js` already has `isValidSignDigest` but it is not called in the sync subscription path. Wiring it in would make the frontend resilient to corrupted-DB scenarios, at the cost of per-row crypto on every sync event.

3. **Notification on failure.** When the checker finds invalid rows, should it emit a PubSub event that triggers an admin notification (e.g. a banner in the admin UI, a log alert on the platform)?

4. **Periodic scheduling.** Should the checker run on a cron (e.g. daily)? If so, it needs to be a supervised periodic task rather than a pure on-demand module. The platform's boot-time sweep may be sufficient for device deployments.

5. **Checking `file_chunks` data integrity.** `FileChunk`'s `Signable` implementation hashes `data_b64` with SHA3-512 before including it in the signature payload. This means the checker verifies that the stored `data_b64` matches what was signed — effectively a content-integrity check for free. Worth calling out in documentation.
