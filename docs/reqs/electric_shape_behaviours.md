# Electric Shape Behaviours

Formalize the per-shape logic for Electric ingestion and peer sync into a single behaviour. Today each shape's validation, authorization, preconditions, and write logic is scattered across `Validation`, `ShapeWriter`, `ElectricController`, and `Versioning`. The behaviour makes each shape self-describing: one module per shape declares everything both pipelines need.

## Problem

Two pipelines consume the same shapes with different trust models:

1. **HTTP ingestion** — a client submits mutations via `POST /electric/v1/ingest`. The server validates Proof-of-Possession, builds changesets through `Phoenix.Sync.Writer`, and writes to local PostgreSQL. The data is then served to other clients and to peer servers via Electric shape streaming.

2. **Peer sync** — another server streams shapes via `Electric.Client`. The receiving server validates signatures and writes to its own PostgreSQL. No PoP — peer sync is a trusted internal operation, but cryptographic integrity (signatures, timestamps) is still verified.

Both pipelines share the integrity triad ([02_integrity.md](../electric/pq_data_layer/02_integrity.md)) and, for versioned shapes, the two-table archiving pattern ([03_data_versioning.md](../electric/pq_data_layer/03_data_versioning.md)). But the shape-specific logic — whose key to check, what preconditions to enforce, how to write — is spread across multiple modules with no unifying contract.

As the shape inventory grows (dialog tables, file storage tables), this scatter becomes a maintenance problem. Each new shape requires touching 4-5 files with no compile-time guarantee that all callbacks are wired up.

## Shape inventory

| Shape | Schema | Integrity triad | Versioned | Owner key source | Preconditions (peer sync) |
|---|---|---|---|---|---|
| `user_card` | `UserCard` | full | no | self (`sign_pkey` in row) | none |
| `user_storage` | `UserStorage` | full | yes → `UserStorageVersion` | parent card (`user_hash`) | card exists |
| `dialog_keys` | `DialogKey` | full | no | parent card (`sender_hash`) | card exists |
| `dialog_messages` | `DialogMessage` | full | yes → `DialogMessageVersion` | parent card (`sender_hash`) | card exists, dialog_keys exists |
| `dialog_message_reactions` | `DialogMessageReaction` | full | no | parent card (`reactor_hash`) | card exists |
| `dialog_message_receipts` | `DialogMessageReceipt` | partial (no `deleted_flag`) | no | parent card (`peer_hash`) | card exists |
| `files` | `File` | full | no | parent card (`uploader_hash`) | card exists |
| `file_chunks` | `FileChunk` | partial (no `deleted_flag`) | no | parent card (`uploader_hash`) | card exists, `files` row exists with matching `uploader_hash` and `deleted_flag = false` |

## Behaviour

```elixir
defmodule Chat.NetworkSynchronization.Electric.Shape do
  @moduledoc """
  Behaviour for Electric-synced shapes.

  Each shape module declares its schema, versioning, and the logic
  for both pipelines. Callbacks are prefixed:
  - `sync_*` — peer sync pipeline only
  - `ingest_*` — HTTP ingestion pipeline only
  - no prefix — used by both or purely declarative

  The generic pipeline handles universal concerns (signature
  verification, timestamp monotonicity, error wrapping, logging).
  """

  @type operation :: :insert | :update
  @type parent_ref :: {shape_name :: atom(), key :: term()}

  # --- Identity ---

  @doc "Atom name used in shape registry, PubSub, and offset storage."
  @callback shape_name() :: atom()

  @doc "Ecto schema module for this shape."
  @callback schema_module() :: module()

  # --- Versioning (optional) ---

  @doc """
  Returns the versions schema module for versioned shapes, or nil.

  When non-nil, both pipelines apply the two-table archiving pattern:
  on update, the outgoing tip is appended to the versions table and the
  master row is rewritten with parent_sign_hash pointing to the archived row.
  """
  @callback versions_schema() :: module() | nil

  # --- Sync: parent dependencies ---

  @doc """
  Returns the parent records this row depends on.

  Called before signature verification. The pipeline checks if each
  parent exists. When any parent is missing, the record is stored in
  the deferred queue (see §Deferred redeliver) with the missing
  parent refs, so it can be retried when parents arrive.

  Returns a list of `{shape_name, key}` tuples. Empty list means
  no dependencies (e.g., user_card is self-rooted).

  Examples:
    user_storage → [{:user_card, user_hash}]
    dialog_messages → [{:user_card, sender_hash}, {:dialog_keys, {dialog_hash, sender_hash}}]
    file_chunks → [{:user_card, uploader_hash}, {:files, file_id}]
  """
  @callback sync_required_parents(operation(), struct()) :: [parent_ref()]

  @doc """
  Validates that a specific parent exists and meets shape-specific
  constraints (e.g., file_chunks requires files.deleted_flag = false
  and matching uploader_hash).

  Called by the pipeline for each parent_ref returned by
  sync_required_parents/2. Returns :ok or {:reject, reason} if the
  parent exists but fails a constraint (e.g., deleted file manifest).
  The pipeline handles the "parent not found" case itself.

  Default implementation (via `using`): returns :ok (existence check
  is sufficient, no extra constraints).
  """
  @callback sync_validate_parent(parent_ref(), struct()) ::
              :ok | {:reject, atom()}

  # --- Sync: derived fields ---

  @doc """
  Computes derived fields from the raw synced struct.

  For shapes with sign_hash: calculates sign_hash from sign_b64.
  Default implementation (via `using`): returns the struct unchanged.
  """
  @callback sync_derive_fields(struct()) :: struct()

  # --- Sync: persist ---

  @doc """
  Persists a validated row to local PostgreSQL.

  Called after parents are verified, fields are derived, and
  signature/timestamp checks pass. Implements shape-specific
  upsert/conflict/versioning logic.
  """
  @callback sync_persist(operation(), struct()) ::
              {:ok, term()} | {:error, term()}

  # --- Ingest: Writer configuration ---

  @doc """
  Configures Phoenix.Sync.Writer for HTTP ingestion of this shape.

  Calls Writer.allow/3 with shape-specific :accept, :check (PoP
  authorization), :validate (changeset + signature), and optional
  :pre_apply (versioning, side effects) callbacks.
  """
  @callback ingest_configure_writer(Writer.t(), pop_context :: map()) :: Writer.t()
end
```

## Deferred redeliver

Electric streams are offset-based: once a record passes the consumer, it won't be redelivered until the next full sync (offset reset). When `sync_required_parents/2` names a parent that doesn't exist yet, dropping the record silently means waiting for a full re-sync to pick it up — potentially minutes of backoff.

The deferred redeliver mechanism solves this by tracking skipped records and retrying them as soon as their parents arrive.

### Data model

Each skipped record is stored as a reference, not the full struct (file_chunks can be ~1 MB):

```elixir
%DeferredRecord{
  shape: :file_chunks,                          # what was skipped
  key: {file_id, chunk_index},                  # primary key (from Ecto.primary_key/1)
  operation: :insert,
  missing_parents: [{:files, file_id}],         # what it's waiting for
  peer_url: "http://192.168.1.5:4444",          # where to re-fetch
  deferred_at: System.monotonic_time()
}
```

### Flow

```
1. ShapeConsumer receives {:change, op, value}

2. Pipeline calls shape_mod.sync_required_parents(op, value)
   → [{:user_card, "u_abc..."}, {:files, "f_xyz..."}]

3. Pipeline checks each parent:
   a. Look up parent shape module via Shapes.by_name(:user_card)
   b. Check existence via repo().get(parent_schema, key)
   c. If exists, call shape_mod.sync_validate_parent({:user_card, key}, value)

4. If any parent missing or rejected:
   → Store DeferredRecord in DeferredStore (ETS)
     keyed by each missing parent_ref
   → return {:ok, :deferred}

5. If all parents present and valid:
   → Continue pipeline: sync_derive_fields → verify signature
     → check timestamp → sync_persist

6. After any successful sync_persist:
   → Extract {shape_name, primary_key} from the written record
   → Look up DeferredStore for records waiting on this parent_ref
   → Move matches to redeliver queue

7. Redeliver queue:
   → For each deferred record, re-fetch from peer via targeted
     Electric shape request with WHERE filter on primary key
   → Feed re-fetched record through the full pipeline (step 2)
   → Recursive: if a redelivered record is itself a parent
     of other deferred records, those get unblocked too
```

### Storage

`DeferredStore` is shared across all ShapeConsumers (a parent from one peer can unblock a child from another peer). Implementation: ETS table under `NetworkSynchronization.Supervisor`.

Index: `{parent_shape, parent_key}` → list of `DeferredRecord`s. A record with multiple missing parents appears under each missing parent's key. On redeliver, the pipeline re-checks all parents (some may still be missing).

### Redeliver strategy

Redelivery re-fetches from the original peer via a short-lived Electric shape stream with a WHERE filter on the record's primary key. This avoids storing potentially large structs (file_chunks) in memory while waiting.

If the peer is unreachable at redeliver time, the deferred record stays in the queue. The next full sync (offset reset on reconnect) will pick it up naturally.

### Cleanup

- When a PeerSync is terminated (peer removed), purge all DeferredRecords for that `peer_url`.
- When a ShapeConsumer does a full re-sync (`must_refetch`), purge DeferredRecords for that `{peer_url, shape}` — the full sync will redeliver everything.
- TTL: deferred records older than 1 hour are purged (the peer has likely reconnected and done a full sync by then).

## Generic pipeline

The behaviour enables two generic pipeline modules that handle universal concerns:

### Peer sync pipeline

Replaces the current `ShapeWriter.do_write/3` pattern match with a generic dispatch:

```
ShapeConsumer
  → {:change, op, value}
  → shape_mod.sync_required_parents(op, value)
      → pipeline checks each parent exists + sync_validate_parent
      → any missing/rejected? → store in DeferredStore, return {:ok, :deferred}
  → shape_mod.sync_derive_fields(value)
  → Integrity.verify_signature(value)
      invalid? → log warning, return {:ok, value}
  → validate_timestamp_newer(op, value)
      stale? → return {:ok, value}
  → shape_mod.sync_persist(op, value)
      success? → check DeferredStore for children to redeliver
```

Signature verification, timestamp checks, deferred tracking, error wrapping, and logging are in the pipeline — not in per-shape code.

### HTTP ingestion pipeline

`ElectricController.config_writer/2` becomes a fold over registered shapes:

```
Writer.new()
|> Shapes.all()
   |> Enum.reduce(writer, fn shape_mod, w ->
        shape_mod.ingest_configure_writer(w, pop_context)
      end)
|> Writer.apply(mutations, repo(), format: Format.TanstackDB)
```

Each shape's `ingest_configure_writer/2` calls `Writer.allow/3` with its own callbacks. The controller no longer knows about individual shapes.

## Per-shape implementations

### `Shape.UserCard`

Self-rooted shape — no parents. The `sign_pkey` is in the row itself.

```elixir
def shape_name, do: :user_card
def schema_module, do: UserCard
def versions_schema, do: nil

def sync_required_parents(_op, _card), do: []

def sync_persist(:insert, card) do
  card |> UserCard.create_changeset(attrs) |> User.upsert_card()
end

def sync_persist(:update, card) do
  # fetch existing, validate timestamp, update
end

def ingest_configure_writer(writer, pop_context) do
  Writer.allow(writer, UserCard,
    accept: [:insert, :update],
    check: &user_card_pop_check(&1, pop_context),
    validate: &user_card_changeset/3
  )
end
```

### `Shape.UserStorage`

Versioned shape. Parent: `user_card` by `user_hash`.

```elixir
def shape_name, do: :user_storage
def schema_module, do: UserStorage
def versions_schema, do: UserStorageVersion

def sync_required_parents(_op, %{user_hash: hash}), do: [{:user_card, hash}]

def sync_derive_fields(%{sign_b64: sign_b64} = storage) when is_binary(sign_b64) do
  %{storage | sign_hash: sign_b64 |> EnigmaPq.hash() |> UserStorageSignHash.from_binary()}
end

def sync_persist(:insert, storage) do
  # validate, check existing, upsert or insert_with_conflict
end

def sync_persist(:update, storage) do
  # validate, fetch existing, update_with_versioning
end

def ingest_configure_writer(writer, pop_context) do
  Writer.allow(writer, UserStorage,
    accept: [:insert, :update],
    check: &user_storage_pop_check(&1, pop_context),
    validate: &user_storage_changeset_with_versioning/3,
    insert: [pre_apply: &user_storage_archive_existing/3],
    update: [pre_apply: &user_storage_archive_existing/3]
  )
end
```

### `Shape.DialogKeys`

Parent: `user_card` by `sender_hash`. LWW upsert, no versioning.

```elixir
def shape_name, do: :dialog_keys
def schema_module, do: DialogKey
def versions_schema, do: nil

def sync_required_parents(_op, %{sender_hash: hash}), do: [{:user_card, hash}]

def sync_persist(_op, dialog_key) do
  # upsert with LWW by owner_timestamp
end

def ingest_configure_writer(writer, pop_context) do
  Writer.allow(writer, DialogKey,
    accept: [:insert, :update],
    check: &dialog_key_pop_check(&1, pop_context),
    validate: &dialog_key_changeset/3
  )
end
```

### `Shape.DialogMessages`

Versioned shape. Parents: `user_card` by `sender_hash` and `dialog_keys` by `{dialog_hash, sender_hash}`.

```elixir
def shape_name, do: :dialog_messages
def schema_module, do: DialogMessage
def versions_schema, do: DialogMessageVersion

def sync_required_parents(_op, %{sender_hash: hash, dialog_hash: dialog_hash}) do
  [{:user_card, hash}, {:dialog_keys, {dialog_hash, hash}}]
end

def sync_derive_fields(%{sign_b64: sign_b64} = msg) when is_binary(sign_b64) do
  %{msg | sign_hash: compute_sign_hash(sign_b64)}
end

def sync_persist(:insert, message) do
  # insert, handle conflict with versioning
end

def sync_persist(:update, message) do
  # archive existing tip, update with versioning
end

def ingest_configure_writer(writer, pop_context) do
  Writer.allow(writer, DialogMessage,
    accept: [:insert, :update],
    check: &dialog_message_pop_check(&1, pop_context),
    validate: &dialog_message_changeset_with_versioning/3,
    insert: [pre_apply: &dialog_message_archive_existing/3],
    update: [pre_apply: &dialog_message_archive_existing/3]
  )
end
```

### `Shape.DialogMessageReactions`

Parent: `user_card` by `reactor_hash`. LWW upsert, no versioning.

```elixir
def shape_name, do: :dialog_message_reactions
def schema_module, do: DialogMessageReaction
def versions_schema, do: nil

def sync_required_parents(_op, %{reactor_hash: hash}), do: [{:user_card, hash}]

def sync_persist(_op, reaction) do
  # upsert with LWW by owner_timestamp
end

def ingest_configure_writer(writer, pop_context) do
  Writer.allow(writer, DialogMessageReaction,
    accept: [:insert, :update],
    check: &reaction_pop_check(&1, pop_context),
    validate: &reaction_changeset/3
  )
end
```

### `Shape.DialogMessageReceipts`

Parent: `user_card` by `peer_hash`. LWW upsert, no versioning, no `deleted_flag`.

```elixir
def shape_name, do: :dialog_message_receipts
def schema_module, do: DialogMessageReceipt
def versions_schema, do: nil

def sync_required_parents(_op, %{peer_hash: hash}), do: [{:user_card, hash}]

def sync_persist(_op, receipt) do
  # upsert with LWW by owner_timestamp
end

def ingest_configure_writer(writer, pop_context) do
  Writer.allow(writer, DialogMessageReceipt,
    accept: [:insert],
    check: &receipt_pop_check(&1, pop_context),
    validate: &receipt_changeset/3
  )
end
```

### `Shape.Files`

The `files` table is a signed manifest created after all chunks are uploaded. Parent: `user_card` by `uploader_hash`.

On HTTP ingest the server validates that all chunks are present and their `sign_b64` hashes match `chunk_sign_hashes`. On peer sync it is a normal signature-verified upsert — chunk verification is deferred to when `file_chunks` arrive (see `Shape.FileChunks`).

When a `files` row is successfully persisted via sync, the pipeline checks the DeferredStore — any `file_chunks` waiting on this `{:files, file_id}` are moved to the redeliver queue.

```elixir
def shape_name, do: :files
def schema_module, do: File
def versions_schema, do: nil

def sync_required_parents(_op, %{uploader_hash: hash}), do: [{:user_card, hash}]

def sync_persist(_op, file) do
  # upsert with LWW by owner_timestamp
end

def ingest_configure_writer(writer, pop_context) do
  Writer.allow(writer, File,
    accept: [:insert, :update],
    check: &file_manifest_pop_check(&1, pop_context),
    validate: &file_manifest_verify_chunks/3
    # validate: all chunk_count chunks exist in file_chunks,
    # each SHA3-256(chunk.sign_b64) matches chunk_sign_hashes[index].
    # On success, deletes corresponding upload_files rows.
  )
end
```

**Signable note**: standard — `sign_b64` covers all other fields including `chunk_sign_hashes`.

### `Shape.FileChunks`

Chunks carry encrypted blob data (~1 MB each). Their `sign_b64` covers a **hash** of `data_b64` (not `data_b64` itself) to avoid re-reading the blob during verification. The Signable protocol implementation must compute `SHA3-256(data_b64)` and substitute it into the signature payload.

On HTTP ingest the server writes a side-effect bookkeeping row to `upload_files` (local-only table, not Electric-synced) with server-set `updated_at` from TimeKeeper for budget/GC tracking.

Parents: `user_card` by `uploader_hash` and `files` by `file_id`. The `files` parent has extra constraints checked via `sync_validate_parent/2`: `uploader_hash` must match and `deleted_flag` must be `false`.

Chunks arriving before their `files` manifest are deferred — when the manifest arrives and is persisted, the deferred chunks are re-fetched from the peer automatically.

```elixir
def shape_name, do: :file_chunks
def schema_module, do: FileChunk
def versions_schema, do: nil

def sync_required_parents(_op, %{uploader_hash: hash, file_id: file_id}) do
  [{:user_card, hash}, {:files, file_id}]
end

def sync_validate_parent({:files, file_id}, %{uploader_hash: uploader_hash}) do
  case Files.get(file_id) do
    %{uploader_hash: ^uploader_hash, deleted_flag: false} -> :ok
    %{deleted_flag: true} -> {:reject, :file_deleted}
    %{} -> {:reject, :uploader_mismatch}
  end
end

def sync_validate_parent(_parent_ref, _chunk), do: :ok

def sync_persist(_op, chunk) do
  # insert with on_conflict: :nothing (chunks are write-once)
end

def ingest_configure_writer(writer, pop_context) do
  Writer.allow(writer, FileChunk,
    accept: [:insert],
    check: &file_chunk_pop_check(&1, pop_context),
    validate: &file_chunk_verify_signature/3
    # signature covers SHA3-256(data_b64), not data_b64 itself
    # side effect: insert upload_files bookkeeping row with TimeKeeper timestamp
  )
end
```

**Signable note**: non-standard. The `Signable` protocol implementation for `FileChunk` must replace `data_b64` with `SHA3-256(data_b64)` in the signable fields map, since the signature covers the hash of the blob, not the blob itself.

## Shape registry

`Shapes` becomes a lookup over behaviour-implementing modules:

```elixir
defmodule Chat.NetworkSynchronization.Electric.Shapes do
  @shapes [
    Shape.UserCard,
    Shape.UserStorage,
    Shape.DialogKeys,
    Shape.DialogMessages,
    Shape.DialogMessageReactions,
    Shape.DialogMessageReceipts,
    Shape.Files,
    Shape.FileChunks
  ]

  def all, do: @shapes
  def by_name(name), do: Enum.find(@shapes, &(&1.shape_name() == name))
  def by_schema(mod), do: Enum.find(@shapes, &(&1.schema_module() == mod))
end
```

## What moves where

| Current location | What | Moves to |
|---|---|---|
| `Validation.validate_user_card_insert/1` | peer sync card validation | `Shape.UserCard.sync_persist/2` |
| `Validation.validate_user_card_update/2` | peer sync card update validation | `Shape.UserCard.sync_persist/2` |
| `Validation.validate_user_storage_insert/1` | peer sync storage validation | `Shape.UserStorage.sync_persist/2` |
| `Validation.validate_user_storage_update/2` | peer sync storage update validation | `Shape.UserStorage.sync_persist/2` |
| `Validation.user_card_allowed/2` | HTTP PoP check for cards | `Shape.UserCard.ingest_configure_writer/2` |
| `Validation.user_card_validate/3` | HTTP card changeset validation | `Shape.UserCard.ingest_configure_writer/2` |
| `Validation.user_storage_allowed/2` | HTTP PoP check for storage | `Shape.UserStorage.ingest_configure_writer/2` |
| `Validation.user_storage_validate_with_versioning/3` | HTTP storage validation + versioning | `Shape.UserStorage.ingest_configure_writer/2` |
| `Validation.user_storage_pre_apply_versioning/3` | HTTP storage pre-apply hook | `Shape.UserStorage.ingest_configure_writer/2` |
| `ShapeWriter.do_write/3` (pattern match) | peer sync dispatch | generic pipeline + `Shape.*.sync_persist/2` |
| `ShapeWriter` parent checks | peer sync preconditions | `Shape.*.sync_required_parents/2` + pipeline |
| `ShapeWriter` sign_hash calculation | peer sync derived fields | `Shape.*.sync_derive_fields/1` |
| `ElectricController.config_writer/2` | HTTP writer setup | generic fold over `Shapes.all()` via `ingest_configure_writer/2` |
| _(new)_ | deferred record tracking | `DeferredStore` + redeliver queue |

`Validation` retains the pure helpers used by multiple shapes:
- `validate_signature/1` — signature verification via Integrity protocol
- `validate_timestamp_newer_than_existing/1` — timestamp monotonicity check

## Migration path

1. Define the `Shape` behaviour module with `@callback` declarations and a `__using__` macro providing defaults for `sync_derive_fields/1`, `sync_validate_parent/2`, and `versions_schema/0`.
2. Implement `Shape.UserCard` and `Shape.UserStorage` extracting logic from current modules.
3. Build the generic sync pipeline: replace `ShapeWriter.do_write/3` pattern match with dispatch through `sync_required_parents/2` → `sync_derive_fields/1` → verify → `sync_persist/2`.
4. Build `DeferredStore` (ETS) and redeliver queue under `NetworkSynchronization.Supervisor`. Wire post-persist hook to check for deferred children.
5. Update `ElectricController` to fold `ingest_configure_writer/2` over registered shapes.
6. Verify existing tests pass with no behavior change.
7. Implement dialog shape modules (`Shape.DialogKeys`, `Shape.DialogMessages`, etc.) as their schemas are created.
8. Implement file shape modules (`Shape.Files`, `Shape.FileChunks`) — note the non-standard `Signable` implementation for `FileChunk` and the cross-table `sync_validate_parent/2` for chunk→manifest constraint.
