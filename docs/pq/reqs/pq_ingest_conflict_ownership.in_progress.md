# Ingest Conflict Ownership Detection

## Problem

When a client sends a mutation and the response is lost (network break after server accepted), the client must retry with the same payload. The server responds with a conflict ("record already exists"). The client cannot tell whether the existing record is **its own** (safe to drop from outbox) or **someone else's** with the same key (collision/race — dropping means data loss).

Today the client resolves this by fetching the row from the shape stream and comparing `sign_b64` byte-by-byte. This approach has caused three distinct bugs — base64 padding variants, `\x`-hex encoding, `Uint8Array` coercion — because the same logical bytes have multiple wire representations on the client side.

## Solution

Move the comparison to the server, where both values (incoming mutation and stored row) are canonical Elixir binaries. No encoding ambiguity is possible.

### 1. New Shape behaviour callback: `fingerprint/1`

```elixir
# in Chat.Data.Shapes.Shape

@callback fingerprint(struct()) :: binary()
```

Returns a deterministic binary fingerprint of the record's content. Used by the ingest controller to compare an attempted mutation against the existing row on conflict.

**Default implementation** (provided by `use Shape`):

```elixir
@impl true
def fingerprint(record) do
  cond do
    (hash = Map.get(record, :sign_hash)) && hash != nil ->
      sign_hash_to_binary(hash)

    (sig = Map.get(record, :sign_b64)) && sig != nil ->
      EnigmaPq.hash(sig)

    true ->
      raise "#{__MODULE__} has no sign_hash or sign_b64 — implement fingerprint/1"
  end
end

defoverridable fingerprint: 1
```

**Priority order**:
1. `sign_hash` — already a stored SHA3-512 digest; cheapest path, no recomputation
2. `sign_b64` — hash it on the fly via `EnigmaPq.hash/1` (SHA3-512)
3. Raise — forces shapes without either field to provide an explicit implementation

The `sign_hash_to_binary/1` helper normalizes the typed `sign_hash` value (e.g. `OriginSignHash`, `ReviewPostRightSignHash`) back to raw binary for comparison. Each type module wraps a binary, so this is a single `type.to_binary(hash)` or pattern match.

### 2. Shape coverage

| Shape | Path | Notes |
|-------|------|-------|
| dialog_messages | sign_hash (stored) | |
| file | sign_hash (stored) | |
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

### 3. Controller changes: `apply_single_mutation/2` conflict handling

When `Writer.apply` returns a unique constraint error inside `apply_single_mutation`:

```
Client                              Server
  |                                   |
  |-- POST /electric/v1/ingest_each ->|
  |   [mutation with sign_b64]        |
  |                                   |-- Writer.apply
  |                                   |     → unique constraint violation
  |                                   |-- identify table → shape module
  |                                   |-- extract PK from changeset
  |                                   |-- fetch existing row from DB
  |                                   |-- compare:
  |                                   |     fingerprint(existing)
  |                                   |     == fingerprint(attempted)
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

**Implementation sketch** in `apply_single_mutation`:

```elixir
defp apply_single_mutation(writer, {index, decode_result}) do
  with {:ok, mutation} <- decode_result,
       {:ok, txid, _changes} <-
         Writer.apply(writer, [mutation], repo(),
           format: Format.TanstackDB,
           timeout: @ingest_timeout
         ) do
    %{index: index, status: "ok", txid: txid}
  else
    {:error, _, %Ecto.Changeset{} = changeset, _} ->
      case detect_conflict(changeset, mutation) do
        {:exists, conflicted} ->
          %{index: index, status: "exists", conflicted: conflicted}

        :not_conflict ->
          Map.merge(%{index: index, status: "error"}, format_mutation_error({:error, nil, changeset, nil}))
      end

    {:error, reason} when is_binary(reason) ->
      %{index: index, status: "error", error: reason}

    error ->
      Map.merge(%{index: index, status: "error"}, format_mutation_error(error))
  end
end
```

**`detect_conflict/2`** determines if a changeset error is a unique constraint violation, fetches the existing row, and compares content identifiers:

```elixir
defp detect_conflict(changeset, mutation) do
  with true <- unique_key_conflict?(changeset),
       {:ok, shape_mod} <- Shapes.module_for_table(mutation["relation"]),
       {:ok, existing} <- fetch_existing(shape_mod, changeset) do
    attempted_id = shape_mod.fingerprint(build_struct(shape_mod, mutation))
    existing_id = shape_mod.fingerprint(existing)
    {:exists, attempted_id != existing_id}
  else
    _ -> :not_conflict
  end
end
```

### 4. Batch ingest (`POST /electric/v1/ingest`)

The batch endpoint uses a single transaction (all-or-nothing). A conflict fails the entire batch. The same conflict detection logic applies here:

When `Writer.apply` returns a unique constraint error, `ingest/2` runs `detect_conflict/2` on the failed changeset. If it's a conflict:

```json
{"status": "exists", "conflicted": false}
```

If it's not a recognized conflict (or the fingerprint comparison fails), the existing error handling applies unchanged.

```elixir
def ingest(conn, params) do
  with {_, %{"mutations" => mutations}} <- {:correct_params, params},
       ...
       {:ok, txid, changes} <-
         Writer.new()
         |> config_writer(user_pop_context)
         |> Writer.apply(mutations, repo(), ...) do
    conn
    |> put_promotion_headers(changes)
    |> json(%{txid: txid})
  else
    {:error, _, %Ecto.Changeset{} = changeset, _} ->
      case detect_conflict(changeset, mutations) do
        {:exists, conflicted} ->
          conn |> put_status(:conflict) |> json(%{status: "exists", conflicted: conflicted})

        :not_conflict ->
          handle_ingest_error(conn, {:error, nil, changeset, nil})
      end

    error -> handle_ingest_error(conn, error)
  end
end
```

For batch, `detect_conflict/2` receives the full mutations list and uses the changeset's table/PK to identify which mutation caused the conflict. Since the transaction is all-or-nothing, only one conflict needs to be reported — the one that broke the batch.

### 5. Required supporting changes

1. **`Shapes.module_for_table/1`** — look up shape module by Ecto table name (or `relation` from the mutation). May already exist in registry; if not, add a reverse lookup from `schema_module().__ schema__(:source)` → shape module.

2. **`unique_key_conflict?/1`** — generalize the existing `pub_key_unique_conflict?/1` to detect any unique constraint violation, not just `pub_key`.

3. **`fetch_existing/2`** — given a shape module and the failed changeset, extract PK fields from `changeset.data` / `changeset.changes` and query the existing row. Single `Repo.get/2` or `Repo.get_by/2` — one indexed PK lookup per conflict.

4. **`sign_hash_to_binary/1`** — extract raw binary from typed sign_hash wrappers. If all `*SignHash` types implement a common protocol or share a structure, this is one function. Otherwise, delegate to `shape_mod.schema_module()` for the type coercion.

### 6. Hash algorithm

`EnigmaPq.hash/1` uses `:crypto.hash(:sha3_512, data)` — **SHA3-512**.

Some documentation references SHA3-256 in hashing contexts — those refer to symmetric key derivation for AES (the only place where SHA3-256 is used). All content hashing uses SHA3-512. The `fingerprint` default must use the same algorithm as `sync_derive_fields` to ensure stored `sign_hash` values match on-the-fly computation from `sign_b64`.

---

## Open Questions

1. **Should `fingerprint` be exposed to peer sync?** The peer sync pipeline (`ShapeWriter`) could use the same mechanism for dedup on receive. Currently out of scope — peer sync has its own validation — but the callback is available if needed.

2. **Rate of conflicts in practice?** If conflicts are rare (expected), the extra `SELECT` per conflict is negligible. If a client is in a retry storm, the DB lookups are still cheap (PK index), but we could cache `{table, PK} → content_id` in the PoP session ETS if needed.

## File Map

| Concern | File |
|---------|------|
| Shape behaviour + default `fingerprint` | `lib/chat/data/shapes/shape.ex` |
| Shape registry (reverse lookup) | `lib/chat/data/shapes.ex` |
| Ingest controller (conflict handling) | `lib/chat_web/controllers/electric_controller.ex` |
| Hash function | `lib/enigma_pq/enigma_pq.ex` (`hash/1` — SHA3-512) |
