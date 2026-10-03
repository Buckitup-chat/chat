# electric_live/

Sandboxes are **reference implementations for the future frontend**. They prove that an external HTTP client — one with no access to Elixir internals — can drive every workflow end-to-end through the Electric HTTP API alone. Every sandbox must behave as a frontend would: raw HTTP requests only.

## HTTP-only rule

Sandbox code must interact exclusively at the HTTP level:

- **Reads**: `GET /electric/v1/shapes?table=...` via `Req` — parse the JSON response, handle pagination, fold the shape log. Do not use `ShapeReader`, `Electric.Client`, `Ecto`, `Db.repo()`, or any other Elixir-side shortcut.
- **Writes**: `GET /electric/v1/challenge` + `POST /electric/v1/ingest` via `Req`.
- **No direct DB access**: no `Repo.get`, no `Repo.get_by`, no Ecto queries of any kind.
- **No Elixir Electric client**: no `Electric.Client.new!`, no `Electric.Client.stream`, no `Phoenix.Sync.client!()`, no `ShapeReader.collect/2`.

If a sandbox needs data, it fetches it over HTTP the same way a JS/TS frontend would. The only Elixir-specific code allowed is crypto (signing, encryption) and struct construction for signature payloads.

### Shape read folding

A one-shot shape read must **fold** the response log, not filter to inserts. Electric replays a cached shape as a snapshot of inserts followed by every change since — keeping only inserts returns rows as they were before their first update. Fold by row key: inserts/updates upsert, deletes remove.

### bytea encoding

The `/electric/v1/shapes` endpoint routes through `HexToBase64Electric`, which normalizes bytea values to unpadded base64 (unlike `Phoenix.Sync.client!()` or `Electric.Client` which return PostgreSQL's raw `\x` hex). This is another reason to stay on the HTTP path.

Note: the above does not apply to non-sandbox LiveView streams using `sync_stream_fixed` — the Ecto schema parser handles type conversion automatically.

Every sub-page must include a back link to the Electric index at the top of its render:

```heex
<a href="/electric" class="text-sm text-blue-600 hover:text-blue-800 mb-2 inline-block">
  &larr; Electric Index
</a>
```

## Sandbox UI conventions

- **Shortcodes for hashes**: Display truncated hashes using `Chat.Proto.Shortcode.short_code/1` protocol. Implementations exist for `BitString` (raw hash strings), `Atom` (nil), and Ecto schemas like `UserCard`.
- **Request log**: Always show full details — request headers, request body, response headers, and response body — each in a collapsible `<details>` block.
- **Form state preservation**: Forms with interactive controls (e.g. star rating buttons via `phx-click`) must use `phx-change` to capture all field values into assigns, and bind those assigns back to the inputs (e.g. `selected={... == @assign}` on `<option>`, `value={@assign}` on `<input>`). Otherwise, re-renders from non-form events reset untracked fields.
