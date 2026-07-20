# electric_live/

This directory exists to prove that external clients can consume the Electric shape endpoints provided by the chat application. Each LiveView here acts as a reference implementation demonstrating real-time sync via Phoenix.Sync + ElectricSQL.

Do not use Ecto queries directly — consume data through shape endpoints only (see memory: `feedback_no_direct_db_in_electric`).

Do not use `Phoenix.Sync.client!()` or the embedded Electric client directly. It bypasses the HTTP layer and returns PostgreSQL's raw `\x` hex encoding for bytea fields instead of base64. Instead, use the `/electric/v1/shapes` endpoint: `Electric.Client.new!(endpoint: base_url <> "/electric/v1/shapes")`. This routes through `HexToBase64Electric`, which normalizes bytea values to unpadded base64. Note: this does not apply to LiveView streams using `sync_stream_fixed` — the Ecto schema parser handles type conversion automatically.

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
