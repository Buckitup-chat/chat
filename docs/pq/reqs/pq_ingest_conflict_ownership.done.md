# Ingest Conflict Ownership Detection

## Problem

When a client sends a mutation and the response is lost (network break after server accepted), the client must retry with the same payload. The server responds with a conflict ("record already exists"). The client cannot tell whether the existing record is **its own** (safe to drop from outbox) or **someone else's** with the same key (collision/race — dropping means data loss).

Today the client resolves this by fetching the row from the shape stream and comparing `sign_b64` byte-by-byte. This approach has caused three distinct bugs — base64 padding variants, `\x`-hex encoding, `Uint8Array` coercion — because the same logical bytes have multiple wire representations on the client side.

## Solution

Move the comparison to the server, where both values (incoming mutation and stored row) are canonical Elixir binaries. No encoding ambiguity is possible.

### 1. Shape behaviour callback: `fingerprint/1`

> `lib/chat/data/shapes/shape.ex:82` — callback definition
> `lib/chat/data/shapes/shape.ex:116-127` — default implementation (injected via `use Shape`)
> `lib/chat/data/shapes/shape.ex:86-90` — `sign_hash_to_binary/1` helper

Returns a deterministic binary fingerprint of the record's content. Used by the ingest controller to compare an attempted mutation against the existing row on conflict.

**Priority order** (pattern-matched in `case record do`):
1. `%{sign_hash: hash} when is_binary(hash)` — already a stored SHA3-512 digest; cheapest path, extracts raw binary via `sign_hash_to_binary/1`
2. `%{sign_b64: sig} when is_binary(sig)` — hash on the fly via `EnigmaPq.hash/1` (SHA3-512)
3. `_` — raises, forcing shapes without either field to provide an explicit implementation

The `sign_hash_to_binary/1` helper extracts the raw 64-byte hash from any `PrefixedHash` type by taking the last 128 hex characters. All `*SignHash` types (`lib/chat/data/types/prefixed_hash.ex`) share this structure: `prefix <> 128_hex_chars`.

### 2. Shape coverage

| Shape | Path | Notes |
|-------|------|-------|
| dialog_messages | sign_hash (stored) | |
| file | sign_b64 → hash | No stored sign_hash |
| origin | sign_hash (stored) | |
| review | sign_hash (stored) | |
| review_list | sign_hash (stored) | |
| review_post_right | sign_hash (stored) | Not HTTP-ingestible; server-side only |
| review_revoke_right | sign_hash (stored) | Not HTTP-ingestible; server-side only |
| review_public_passwords | sign_hash (stored) | |
| user_storage | sign_hash (stored) | |
| review_password_candidate | sign_hash (stored) | |
| review_post_right_candidate | sign_hash (stored) | Update-only ingest |
| review_revoke_right_candidate | sign_hash (stored) | Update-only ingest |
| user_card | sign_b64 → hash | No stored sign_hash; default hashes on the fly |
| dialog_keys | sign_b64 → hash | No stored sign_hash |
| dialog_message_reactions | sign_b64 → hash | No stored sign_hash |
| dialog_message_receipts | sign_b64 → hash | No stored sign_hash |
| file_chunk | sign_b64 → hash | No stored sign_hash |

All 17 shapes are covered by the default implementation. No custom overrides needed today. Future shapes without `sign_b64` must implement `fingerprint/1` explicitly (the raise enforces this at runtime).

### 3. Controller changes: conflict handling

> `lib/chat_web/controllers/electric_controller.ex:80-104` — `apply_single_mutation/2`
> `lib/chat_web/controllers/electric_controller.ex:230-240` — `detect_conflict/1`
> `lib/chat_web/controllers/electric_controller.ex:213-228` — `respond_changeset_error/2`

When `Writer.apply` returns a unique constraint error:

```
Client                              Server
  |                                   |
  |-- POST /electric/v1/ingest_each ->|
  |   [mutation with sign_b64]        |
  |                                   |-- Writer.apply
  |                                   |     → unique constraint violation
  |                                   |-- detect_conflict(changeset)
  |                                   |     → schema_mod from changeset.data
  |                                   |     → shape_mod via Shapes.by_schema
  |                                   |     → fetch existing row by PK
  |                                   |     → compare fingerprints
  |                                   |
  |<-- {index, status, conflicted} ---|
```

Per-mutation result gains a new field on conflict:

```json
{"index": 0, "status": "exists", "conflicted": false}
```

| `status` | `conflicted` | Meaning | Client action |
|----------|-------------|---------|---------------|
| `"ok"` | absent | Normal success | Drop from outbox |
| `"exists"` | `false` | Record exists, content matches yours | Drop from outbox |
| `"exists"` | `true` | Record exists, content differs (race/collision) | Keep in outbox, alert user |
| `"error"` | absent | Validation or other failure | Retry or surface error |

The `ingest_each` overall HTTP status uses `status != "error"` (line 70), so "exists" responses don't downgrade the batch to 422.

### 4. Batch ingest (`POST /electric/v1/ingest`)

> `lib/chat_web/controllers/electric_controller.ex:35-57` — `ingest/2`
> `lib/chat_web/controllers/electric_controller.ex:199-200` — changeset error delegates to `respond_changeset_error/2`

The batch endpoint uses a single transaction (all-or-nothing). A conflict fails the entire batch. The same `detect_conflict/1` logic applies via `respond_changeset_error/2` in `handle_ingest_error`:

- Conflict detected → HTTP 409 with `{"status": "exists", "conflicted": false|true}`
- Not a recognized conflict → falls through to existing `pub_key_unique_conflict?` / validation error handling

### 5. Supporting functions

1. **`Shapes.module_for_table/1`** (`lib/chat/data/shapes.ex:60-67`) — reverse lookup from Ecto table name to shape module. Accepts bare string or `[schema, table]` list.

2. **`unique_key_conflict?/1`** (`lib/chat_web/controllers/electric_controller.ex:256-259`) — generalizes `pub_key_unique_conflict?/1` to detect any unique constraint violation, not just `pub_key`.

3. **`fetch_existing/2`** (`lib/chat_web/controllers/electric_controller.ex:242-254`) — extracts PK fields from `schema_mod.__schema__(:primary_key)`, reads values from changeset via `Ecto.Changeset.get_field/2`, queries via `Repo.get_by/2`. Guards against nil PK values.

4. **`sign_hash_to_binary/1`** (`lib/chat/data/shapes/shape.ex:86-90`) — extracts raw 64-byte binary from any `PrefixedHash` sign_hash string by decoding the last 128 hex characters.

### 6. Hash algorithm

`EnigmaPq.hash/1` (`lib/enigma_pq/enigma_pq.ex:24-26`) uses `:crypto.hash(:sha3_512, data)` — **SHA3-512**.

Some documentation references SHA3-256 in hashing contexts — those refer to symmetric key derivation for AES (the only place where SHA3-256 is used). All content hashing uses SHA3-512. The `fingerprint` default must use the same algorithm as `sync_derive_fields` to ensure stored `sign_hash` values match on-the-fly computation from `sign_b64`.

### 7. Implementation notes

- **`detect_conflict/1`** takes only the changeset (not the mutation) — the schema module and PK are already available from `changeset.data.__struct__` and `Ecto.Changeset.get_field/2`. No need for mutation map access.
- **`Shapes.by_schema/1`** (existing) is used instead of `module_for_table/1` in the conflict path — more direct since the changeset already carries the schema module.
- **`Ecto.Changeset.apply_changes/1`** builds the "attempted" struct for fingerprinting, applying changes regardless of validity.

---

## Open Questions

1. **Should `fingerprint` be exposed to peer sync?** The peer sync pipeline (`ShapeWriter`) could use the same mechanism for dedup on receive. Currently out of scope — peer sync has its own validation — but the callback is available if needed.

2. **Rate of conflicts in practice?** If conflicts are rare (expected), the extra `SELECT` per conflict is negligible. If a client is in a retry storm, the DB lookups are still cheap (PK index), but we could cache `{table, PK} → content_id` in the PoP session ETS if needed.

## File Map

| Concern | File | Lines |
|---------|------|-------|
| Shape behaviour + default `fingerprint` | `lib/chat/data/shapes/shape.ex` | 82, 86-90, 116-127 |
| Shape registry (`module_for_table`) | `lib/chat/data/shapes.ex` | 60-67 |
| Ingest controller (conflict handling) | `lib/chat_web/controllers/electric_controller.ex` | 80-104, 213-240 |
| Hash function | `lib/enigma_pq/enigma_pq.ex` | 24-26 |
| Tests | `test/chat_web/controllers/electric_controller_test.exs` | 82-91 |
