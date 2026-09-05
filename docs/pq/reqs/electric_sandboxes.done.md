# Electric API Sandboxes

## Purpose

Interactive web-based testing clients for the Electric ingest API. Each sandbox embodies a single persona and exercises its CRUD operations with Post-Quantum cryptographic authentication. Together they cover the full user → dialog → origin → review → moderation lifecycle.

## Sandbox inventory

| Route | Persona | Tables exercised | Module root |
|-------|---------|-----------------|-------------|
| `/electric/user_sandbox` | Any user | `user_card`, `user_storage` | `UserSandboxLive` |
| `/electric/dialog_sandbox` | Two chat participants | `dialog_keys`, `dialog_messages`, `dialog_reactions`, `dialog_receipts` | `DialogSandboxLive` |
| `/electric/origin_sandbox` | Origin owner | `user_card` (origin), `origin` | `OriginSandboxLive` |
| `/electric/review_sandbox` | Review author | `review`, `review_post_right`, `review_revoke_right`, `review_public_passwords`, `review_list`, `dialog_keys`, `dialog_messages` | `ReviewSandboxLive` |
| `/electric/moderation_sandbox` | Origin moderator | `review_post_right`, `review_revoke_right`, `review_public_passwords` | `ModerationSandboxLive` |
| `/electric/origin_reviews` | Public (no identity) | `origin`, `review`, `review_public_passwords` | read-only viewer |
| `/electric/contacts_reader` | Contact reader | `review_list`, `review`, `dialog_keys`, `dialog_messages` | `ContactsReaderLive` |
| `/file_sandbox.html` | Any user | `file`, `file_chunk` | static HTML + JS |

All LiveView sandboxes live under `lib/chat_web/live/electric_live/`.

## Shared principles

### P1 — Persona isolation

Each sandbox operates under exactly one role. Identity is ephemeral — stored in LiveView assigns, cleared on page refresh. No backend persistence of sandbox state.

### P2 — Identity via key import

Sandboxes that need authentication accept a `.json` key file upload (`allow_upload(:key_file, accept: ~w(.json))`). Most sandboxes validate identity through `DialogSandboxLive.Crypto.parse_and_validate_identity/1`. The user sandbox has its own `UserSandboxLive.Identity.parse_and_validate/1` (v2 format with secret keys, `crypt_cert`/`contact_cert` verification). The user sandbox also supports in-place PQ key generation.

### P3 — Challenge-response authentication (PQ PoP)

All write operations follow the two-step Proof-of-Possession flow:

1. `POST /electric/v1/challenge` — request a nonce
2. Sign nonce with ML-DSA-87 private key
3. `POST /electric/v1/ingest` — submit signed challenge + mutation payload

No sandbox bypasses this pattern.

### P4 — Shape endpoints only

Data reads go through `/electric/v1/shapes` HTTP endpoints (via `Electric.Client` or `ShapeReader`), never through Ecto queries. Bytea fields are normalized from PostgreSQL `\x` hex to unpadded base64 by `HexToBase64Electric` middleware.

### P5 — Request log accumulation

Every API call returns `log_entries` alongside its result. Write sandboxes accumulate these into a `request_log` assign. The shared `RequestLog` component (`request_log.ex`) or an inline equivalent renders each entry with collapsible sections for request headers, request body, response headers, and response body. The read-only origin reviews viewer is exempt — it makes no ingest calls and has no request log.

### P6 — Error surface without state loss

Write sandboxes carry an `error_message` assign. Failed operations set it; a dismiss button clears it. Errors never reset application state — the sandbox continues from where it was. Failed requests still appear in the request log. The read-only origin reviews viewer has no error surface — shape read failures are silent.

### P7 — In-flight action gating

User and Dialog sandboxes track `operation_in_progress` to disable action buttons during API calls, re-enabled on response (success or failure). Other sandboxes use context-appropriate gating: Origin sandbox gates on `pending_reviews`, Moderation and Contacts reader gate on `loading` (async shape reads). Review sandbox and the read-only origin reviews viewer have no in-flight gating.

### P8 — Back link to Electric index

Every sub-page renders `← Electric Index` linking to `/electric`.

### P9 — Hash shortcodes

Hashes displayed via `Chat.Proto.Shortcode.short_code/1` — never raw hex strings in the UI. The protocol preserves the type prefix and takes the first 6 hex characters (e.g. `u_aabbcc`, `di_112233`).

### P10 — Export/import identity round-trip

Sandboxes that create identities (user, origin) can export them as `.json`. Downstream sandboxes import those exports to continue the flow across personas.

### P11 — Form state preservation

Forms with interactive controls (e.g. star ratings via `phx-click`) use `phx-change` to capture field values into assigns, binding them back to inputs. Otherwise re-renders from non-form events reset untracked fields.

## Per-sandbox details

### User sandbox

- **Create user**: generates ML-DSA-87 + ML-KEM-1024 keypairs, computes `user_hash` as `"u_" + hex(SHA3-512(sign_pkey))`, creates via challenge-response
- **Update name**: change display name, re-sign card
- **Delete user**: soft-delete via `deleted_flag`
- **Storage CRUD**: create/view/edit/delete `user_storage` entries with configurable size (1 byte – 10 MB random binary), optional label, optional UUID
- **Key export/import**: export identity JSON for reuse in other sandboxes
- **Layout**: three-panel (docs sidebar, main content, request log)

### Dialog sandbox

- **Create dialog**: select peer from available users, publish `dialog_keys` row with KEM-wrapped message key
- **Send/edit/delete messages**: encrypted `dialog_messages` with `content_b64` (AES-256-GCM)
- **Reactions**: emoji reactions via `dialog_reactions`
- **Read receipts**: delivery/read via `dialog_receipts`
- **Message versions**: expand to see edit history via shape reads
- **Live streaming**: real-time sync via `start_message_stream` (Electric shape streaming), status indicator (idle → loading → loaded → live)
- **Layout**: three-panel (docs sidebar, main content, request log)

### Origin sandbox

- **Create origin**: generate origin ML-DSA-87 + ML-KEM-1024 keypairs (independent of owner keys), insert origin `user_card` (self-signed), create `origin` row with `owner_cert`
- **Set moderation mode**: pre/post/none
- **Update/delete**: name changes, soft-delete
- **Export origin identity**: JSON with origin signing + encryption secret keys, for import into moderation sandbox
- **Layout**: single-column with request log

### Review sandbox

- **Browse origins**: async load via `ShapeReader` + `Origin` schema
- **Submit review**: select origin, set star rating (1–5), enter text, encrypt with generated `review_password` (AES-256-GCM), ML-DSA-87 sign
- **Rights pipeline**: submit password candidates → server promotes → read right candidates via shape → verify KEM wrapping → sign rights → server completes
- **Review list**: submit entry referencing proof hashes, fill password proof
- **Contacts key sharing**: list peers from dialogs, send `review_list_password` via dialog messages
- **Layout**: single-column with request log

### Moderation sandbox

- **Import origin identity**: parse exported JSON, verify against origin's `user_card` (signature + KEM round-trip)
- **Load queue**: read reviews + right envelopes via shape, KEM-decapsulate rights
- **Publish**: ingest author's pre-signed `review_public_passwords` row (post right)
- **Revoke**: ingest pre-signed null row (revoke right)
- **Layout**: single-column with request log

### Origin reviews (public viewer)

- **No identity required**: read-only, simulates public frontend
- **Browse origins**: list all with moderation mode
- **Decrypt reviews**: use `password_b64` from `review_public_passwords` (AES-256-GCM)
- **Render**: star rating + review text, show moderation state

### Contacts reader

- **Import identity**: verify against `user_card`
- **Discover contacts**: scan dialogs for `review_list_key` messages
- **Read reviews**: fetch per-origin reviews for each contact, decrypt content
- **Badge reviews**: cross-reference `review_public_passwords` — public / hidden / contacts-only

### File sandbox

- **Static HTML**: separate from LiveView sandboxes (`/file_sandbox.html`)
- **Upload/download**: exercises `file` and `file_chunk` tables

## Implementation references

All sandbox source lives under [`lib/chat_web/live/electric_live/`](../../lib/chat_web/live/electric_live/):

- Shared: [`request_log.ex`](../../lib/chat_web/live/electric_live/request_log.ex) — reusable log rendering component
- Shared crypto: [`dialog_sandbox_live/crypto.ex`](../../lib/chat_web/live/electric_live/dialog_sandbox_live/crypto.ex) — identity parsing, key derivation, encryption
- Convention docs: [`electric_live/CLAUDE.md`](../../lib/chat_web/live/electric_live/CLAUDE.md)

### API endpoints

- `POST /electric/v1/challenge` — request authentication challenge
- `POST /electric/v1/ingest` — submit mutations with signed challenge
- `GET /electric/v1/shapes` — read table data via Electric shape protocol

## Status

All seven sandboxes and the file sandbox are implemented and functional. The `/electric` landing page links to all of them with icon cards showing the tables each exercises.
