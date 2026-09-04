# Electric Shape Behaviours

Per-shape logic for Electric ingestion and peer sync, formalized into a single behaviour. Each shape module is self-describing: one module per shape declares everything both pipelines need.

## Problem

Two pipelines consume the same shapes with different trust models:

1. **HTTP ingestion** — a client submits mutations via `POST /electric/v1/ingest`. The server validates Proof-of-Possession, builds changesets through `Phoenix.Sync.Writer`, and writes to local PostgreSQL. The data is then served to other clients and to peer servers via Electric shape streaming.

2. **Peer sync** — another server streams shapes via `Electric.Client`. The receiving server validates signatures and writes to its own PostgreSQL. No PoP — peer sync is a trusted internal operation, but cryptographic integrity (signatures, timestamps) is still verified.

Both pipelines share the integrity triad ([02_integrity.md](../invariants/02_integrity.md)) and, for versioned shapes, the two-table archiving pattern ([03_data_versioning.md](../invariants/03_data_versioning.md)). The behaviour contract ensures each new shape wires up both pipelines with compile-time callback guarantees.

## Shape inventory

Order matters — `user_card` is the FK parent for all other shapes.

| Shape | Schema | Versioned | Owner key source | Sync parents | Syncable |
|---|---|---|---|---|---|
| `user_card` | `UserCard` | no | self (`sign_pkey` in row) | none | yes |
| `user_storage` | `UserStorage` | yes → `UserStorageVersion` | parent card (`user_hash`) | `user_card` | yes |
| `dialog_keys` | `DialogKey` | no | parent card (`sender_hash`) | `user_card` | yes |
| `dialog_messages` | `DialogMessage` | yes → `DialogMessageVersion` | parent card (`sender_hash`) | `user_card`, `dialog_keys` | yes |
| `dialog_message_reactions` | `DialogMessageReaction` | no | parent card (`reactor_hash`) | `user_card` | yes |
| `dialog_message_receipts` | `DialogMessageReceipt` | no | parent card (`peer_hash`) | `user_card` | yes |
| `file` | `File` | no | parent card (`uploader_hash`) | `user_card` | yes |
| `file_chunk` | `FileChunk` | no | parent card (`uploader_hash`) | `file` (with constraints) | yes |
| `origin` | `Origin` | no | parent card (`origin_hash`, `owner_hash`) | `user_card` ×2 | yes |
| `review` | `Review` | no | parent card (`author_hash`) | `user_card` | yes |
| `review_public_passwords` | `ReviewPublicPassword` | no | parent card (`author_hash`) | `user_card` | yes |
| `review_post_right` | `ReviewPostRight` | no | parent card (`author_hash`) | `user_card` | yes |
| `review_revoke_right` | `ReviewRevokeRight` | no | parent card (`author_hash`) | `user_card` | yes |
| `review_password_candidate` | `ReviewPasswordCandidate` | no | parent card (`author_hash`) | `user_card` | **no** |
| `review_post_right_candidate` | `ReviewPostRightCandidate` | no | parent card (`author_hash`) | `user_card` | **no** |
| `review_revoke_right_candidate` | `ReviewRevokeRightCandidate` | no | parent card (`author_hash`) | `user_card` | **no** |
| `review_list` | `ReviewList` | no | parent card (`user_hash`) | `user_card` | yes |

Non-syncable shapes (candidates) are HTTP ingest-only — they participate in the Writer pipeline but are excluded from peer sync consumers.

## Behaviour

[`Chat.Data.Shapes.Shape`](../../lib/chat/data/shapes/shape.ex) defines the behaviour contract.

### Callbacks

```
+------------------+
| Identity         |
|  shape_name/0    |
|  schema_module/0 |
|  versions_schema/0  (default: nil)
+------------------+
         |
+--------v---------+     Peer sync pipeline
| sync_required_   |     (ShapeWriter)
|   parents/2      |---> [{shape, key}]
+------------------+
         |
+--------v---------+
| sync_validate_   |     (default: :ok)
|   parent/2       |---> :ok | {:reject, reason}
+------------------+
         |
+--------v---------+
| sync_derive_     |     (default: identity)
|   fields/1       |---> struct with computed fields
+------------------+
         |
+--------v---------+
| sync_persist/2   |---> {:ok, _} | {:error, _}
+------------------+
         |
+--------v---------+
| sync_after_      |     (default: :ok)
|   persist/3      |---> opts include peer_url when from peer sync
+------------------+

+------------------+     HTTP ingestion pipeline
| ingest_configure_|     (ElectricController)
|   writer/2       |---> Writer.allow(writer, schema, ...)
+------------------+
```

### `__using__` macro

`use Chat.Data.Shapes.Shape` sets up `@behaviour` and provides default implementations for `versions_schema/0` (nil), `sync_validate_parent/2` (:ok), `sync_derive_fields/1` (identity), `sync_after_persist/3` (:ok), and `ingest_configure_writer/2` (passthrough). All are `defoverridable`.

### `persist:` option

Pass `persist:` to `use Shape` to generate standard `sync_persist/2`, `persist_insert/2`, `persist_update/1`, and `apply_changeset/2` from declarative config:

```elixir
use Chat.Data.Shapes.Shape,
  persist: [
    upsert: &ReviewData.upsert_review/1,
    get: &ReviewData.get_review/1,
    lookup_key: :review_hash,                    # atom or list of atoms for composite keys
    validate_insert: &Validation.validate_review_insert/1,
    validate_update: &Validation.validate_review_update/2
  ]
```

Used by: [`Origin`](../../lib/chat/data/shapes/origin.ex), [`Review`](../../lib/chat/data/shapes/review.ex), [`ReviewPostRight`](../../lib/chat/data/shapes/review_post_right.ex), [`ReviewRevokeRight`](../../lib/chat/data/shapes/review_revoke_right.ex), [`ReviewList`](../../lib/chat/data/shapes/review_list.ex).

## Pipelines

### Peer sync pipeline

[`ShapeWriter`](../../lib/chat/network_synchronization/electric/shape_writer.ex) dispatches generically through `Shapes.by_name(shape_name)`.

#### Full flow

```
ShapeConsumer
     │
     ▼
{:change, op, value}
     │
     ▼
┌────────────────────────────────────┐
│  sync_required_parents(op, value)  │
└─────────────────┬──────────────────┘
                  │
                  ▼
         ┌────────────────┐
         │  check parents │  for each {shape, key}:
         │                │    Shapes.by_name → repo.get
         │                │    → sync_validate_parent
         └────────┬───────┘
                  │
           ┌──────┴───────┐
           │              │
      all present    any missing
           │              │
           │         rejected → {:error, {:rejected, reason}}
           │              │
           │         missing → DeferredStore.defer (if peer_url in opts)
           │              │
           │         {:ok, :skipped_no_parent}
           │
           ▼
┌────────────────────────┐
│  sync_derive_fields    │
└───────────┬────────────┘
            │
            ▼
┌────────────────────────┐
│  sync_persist(op, val) │  (signature/timestamp checks inside each shape's Validation)
└───────────┬────────────┘
            │
            ▼
┌────────────────────────┐
│  sync_after_persist    │  (e.g. File: preseed_missing_chunks,
│    (op, result, opts)  │   FileChunk: fill_missing_chunk + SyncSource)
└───────────┬────────────┘
            │
            ▼
┌────────────────────────────────┐
│  notify_deferred_children      │
│  DeferredStore.check_children  │── found? → trigger_redeliver
│  {shape_name, primary_key}     │              │
└────────────────────────────────┘              ▼
                                      Task: re-fetch from peer
                                      via Electric.Client.stream
                                      → ShapeWriter.write ↺
```

#### Deferred redeliver

Electric streams are offset-based: once a record passes the consumer, it won't be redelivered until the next full sync. The deferred redeliver mechanism tracks skipped records and retries them when parents arrive.

**Data model.** [`DeferredRecord`](../../lib/chat/network_synchronization/electric/deferred_record.ex) — each skipped record stored as a reference, not the full struct:

```elixir
%DeferredRecord{
  shape: :file_chunk,
  key: [file_id: file_id, chunk_index: chunk_index],   # Keyword.t() from Ecto.primary_key/1
  operation: :insert,
  missing_parents: [{:file, file_id}],
  peer_url: "http://192.168.1.5:4444",
  deferred_at: System.monotonic_time(:millisecond)
}
```

**Storage.** [`DeferredStore`](../../lib/chat/network_synchronization/electric/deferred_store.ex) is a GenServer with a `:bag` ETS table, shared across all ShapeConsumers. Index: `{parent_shape, parent_key}` → list of `DeferredRecord`s. A record with multiple missing parents appears under each missing parent's key.

**Redeliver strategy.** Redelivery spawns a `Task` under `Chat.TaskSupervisor` that re-fetches from the original peer via a short-lived `Electric.Client.stream` with a WHERE filter (built via `Ecto.Query`) on the record's primary key. Changes are replayed through `ShapeWriter.write/4`.

**Cleanup:**
- `purge_peer/1` — when a PeerSync is terminated (peer removed), purge all DeferredRecords for that `peer_url`.
- `purge_shape/2` — when a ShapeConsumer does a full re-sync (`must_refetch`), purge DeferredRecords for that `{peer_url, shape}`.
- TTL sweep: every 5 minutes, deferred records older than 2 hours are purged via `select_delete`.

### HTTP ingestion pipeline

[`ElectricController.config_writer/2`](../../lib/chat_web/controllers/electric_controller.ex) folds `ingest_configure_writer/2` over all registered shapes:

```elixir
defp config_writer(writer, user_pop_context) do
  Shapes.all()
  |> Enum.reduce(writer, fn shape_mod, w ->
    shape_mod.ingest_configure_writer(w, user_pop_context)
  end)
end
```

The controller also provides `ingest_each/2` for per-mutation error isolation — each mutation is applied independently and returns individual status.

## Per-shape implementations

### [`Shape.UserCard`](../../lib/chat/data/shapes/user_card.ex)

Self-rooted shape — no parents. Custom `sync_persist/2` (not using `persist:` macro) delegates to `Chat.Data.User.Validation` for insert/update validation, `User.upsert_card/1` and `User.update_card/1` for writes.

### [`Shape.UserStorage`](../../lib/chat/data/shapes/user_storage.ex)

Versioned shape (→ `UserStorageVersion`). Parent: `user_card` by `user_hash`. Overrides `sync_derive_fields/1` to compute `sign_hash` from `sign_b64`. Custom `sync_persist/2` delegates to `Chat.Data.User.Validation`, uses `User.insert_storage_with_conflict/2` and `User.update_storage_with_versioning/2`. Ingest writer wires `pre_apply` for versioning on both insert and update.

### [`Shape.DialogKeys`](../../lib/chat/data/shapes/dialog_keys.ex)

Parent: `user_card` by `sender_hash`. Custom `sync_persist/2` with `Dialog.Validation` and `Dialog.upsert_dialog_key/1`.

### [`Shape.DialogMessages`](../../lib/chat/data/shapes/dialog_messages.ex)

Versioned shape (→ `DialogMessageVersion`). Parents: `user_card` by `sender_hash` and `dialog_keys` by `{dialog_hash, sender_hash}`. Overrides `sync_derive_fields/1` for `sign_hash`. Custom `sync_persist/2` with versioning. Ingest writer wires `pre_apply` for versioning.

### [`Shape.DialogMessageReactions`](../../lib/chat/data/shapes/dialog_message_reactions.ex)

Parent: `user_card` by `reactor_hash`. Custom `sync_persist/2` with `Dialog.Validation` and `Dialog.upsert_reaction/1`.

### [`Shape.DialogMessageReceipts`](../../lib/chat/data/shapes/dialog_message_receipts.ex)

Parent: `user_card` by `peer_hash`. Insert-only (no update). Custom `sync_persist/2` with `Dialog.Validation` and `Dialog.upsert_receipt/1`. Ingest writer accepts `[:insert]` only.

### [`Shape.File`](../../lib/chat/data/shapes/file.ex)

Parent: `user_card` by `uploader_hash`. Overrides `sync_derive_fields/1` to decode `chunk_sign_hashes` (`bytea[]`) and `sign_b64` from wire formats (PG hex-escaped or base64). Custom `sync_persist/2` with `File.Validation`. Overrides `sync_after_persist/3` — on insert from peer sync, calls `FileData.insert_missing_chunks_placeholders/4` to preseed expected chunks. Ingest writer wires separate `pre_apply` callbacks for insert and update.

**Signable note**: standard — `sign_b64` covers all other fields including `chunk_sign_hashes`.

### [`Shape.FileChunk`](../../lib/chat/data/shapes/file_chunk.ex)

Insert-only. Parent: `file` by `file_id` (no `user_card` parent — uploader ownership is enforced via `sync_validate_parent/2` against the file manifest). Overrides `sync_validate_parent/2` for `{:file, _}` — checks file exists, `deleted_flag` is false, and `uploader_hash` matches. Overrides `sync_after_persist/3` — on insert from peer sync, calls `FileData.fill_missing_chunk/4` and `SyncSource.chunk_fetchable/4` to signal the chunk pipeline.

**Signable note**: non-standard. The `Signable` protocol implementation for `FileChunk` replaces `data_b64` with `SHA3-512(data_b64)` in the signable fields map.

### [`Shape.Origin`](../../lib/chat/data/shapes/origin.ex)

Parents: `user_card` by both `origin_hash` and `owner_hash`. Uses `persist:` macro with `OriginData.upsert_origin/1`. Overrides `sync_derive_fields/1` for `sign_hash`.

### [`Shape.Review`](../../lib/chat/data/shapes/review.ex)

Parent: `user_card` by `author_hash`. Uses `persist:` macro with `ReviewData.upsert_review/1`. Overrides `sync_derive_fields/1` for `sign_hash`.

### [`Shape.ReviewPublicPasswords`](../../lib/chat/data/shapes/review_public_passwords.ex)

Parent: `user_card` by `author_hash`. Custom `sync_persist/2` (insert-only validation). Overrides `sync_derive_fields/1` for `sign_hash`. Ingest accepts `[:insert]` only, with moderation-specific check/validate callbacks.

### [`Shape.ReviewPostRight`](../../lib/chat/data/shapes/review_post_right.ex)

Parent: `user_card` by `author_hash`. Uses `persist:` macro. Overrides `sync_derive_fields/1` for `sign_hash`. No `ingest_configure_writer` override (uses default passthrough).

### [`Shape.ReviewRevokeRight`](../../lib/chat/data/shapes/review_revoke_right.ex)

Parent: `user_card` by `author_hash`. Uses `persist:` macro. Overrides `sync_derive_fields/1` for `sign_hash`. No `ingest_configure_writer` override.

### [`Shape.ReviewPasswordCandidate`](../../lib/chat/data/shapes/review_password_candidate.ex)

**Not syncable.** Parent: `user_card` by `author_hash`. Insert-only. Ingest wires `post_apply` for candidate promotion.

### [`Shape.ReviewPostRightCandidate`](../../lib/chat/data/shapes/review_post_right_candidate.ex)

**Not syncable.** Parent: `user_card` by `author_hash`. Update-only ingest (server creates the row, client signs via update). Ingest wires `post_apply` for completion.

### [`Shape.ReviewRevokeRightCandidate`](../../lib/chat/data/shapes/review_revoke_right_candidate.ex)

**Not syncable.** Parent: `user_card` by `author_hash`. Update-only ingest. Ingest wires `post_apply` for completion.

### [`Shape.ReviewList`](../../lib/chat/data/shapes/review_list.ex)

Parent: `user_card` by `user_hash`. Uses `persist:` macro with composite `lookup_key: [:user_hash, :review_hash]`. Overrides `sync_derive_fields/1` for `sign_hash`.

## Shape registry

[`Chat.Data.Shapes`](../../lib/chat/data/shapes.ex) — lookup over behaviour-implementing modules:

- `all/0` — all 17 shapes (order matters: `user_card` first)
- `by_name/1` — find shape module by atom name
- `by_schema/1` — find shape module by Ecto schema module
- `shape_names/0` — all shape name atoms
- `sync_shape_names/0` — syncable shape names only (excludes candidates)
- `sync_schemas/0` — all syncable schema modules including version schemas
- `sync_tables/0` — table names for syncable schemas
- `primary_key/1` — delegates to schema's `__schema__(:primary_key)`

The registry distinguishes `@syncable` (14 shapes used in peer sync) from `@not_syncable` (3 candidate shapes that are HTTP ingest-only).

## Implementation status

All migration steps are complete:

1. ✅ `Chat.Data.Shapes.Shape` behaviour with `__using__` macro — [`lib/chat/data/shapes/shape.ex`](../../lib/chat/data/shapes/shape.ex)
2. ✅ All 17 shape modules implemented in [`lib/chat/data/shapes/`](../../lib/chat/data/shapes/)
3. ✅ Generic sync pipeline in [`ShapeWriter`](../../lib/chat/network_synchronization/electric/shape_writer.ex) — dispatch through callbacks, no pattern matching on shape names
4. ✅ `DeferredStore` (GenServer + ETS) and redeliver in [`lib/chat/network_synchronization/electric/`](../../lib/chat/network_synchronization/electric/)
5. ✅ `ElectricController` folds `ingest_configure_writer/2` over `Shapes.all()` — [`lib/chat_web/controllers/electric_controller.ex`](../../lib/chat_web/controllers/electric_controller.ex)
6. ✅ Domain-specific `Validation` modules retained as pure helpers, called by shape callbacks (`Chat.Data.User.Validation`, `Chat.Data.Dialog.Validation`, `Chat.Data.File.Validation`, etc.)
