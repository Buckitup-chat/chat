# Writing a client for a BuckitUp server

For a team building its own client — a web UI on another domain, a backend
service — against an unmodified BuckitUp server. It states what goes over the
wire; the protocol behind each table is in `docs/pq/reqs/`, the signing rules
in [invariants/02_integrity.md](invariants/02_integrity.md).

## Endpoints

All under `https://<host>/electric/v1`. CORS allows any origin.

| Method and path | Purpose |
|---|---|
| `GET /challenge` | A challenge for one key proof: `{challenge_id, challenge, expires_in}`. Single use, 60 s |
| `POST /ingest` | Write a batch of rows in one transaction |
| `POST /ingest_each` | Write rows one by one; a result per row |
| `GET /shapes?table=…&where=…` | Read a table, once or live (Electric HTTP API) |
| `POST /read_session` | Open a read session for a shape (access mode `trust` only) |
| `GET /device_identity` | `{device_id, admin, sync_bot}`: the server's id for scopes and its owner |
| `GET /status` | Readiness: `200` or `503` |
| `GET /system_identifier` | The database's system identifier |
| `PUT /file_chunk/…`, `GET /file_chunk/…` | Encrypted file chunks ([reqs/files](reqs/files)) |

## Key proof

Every write proves possession of the key of the identity it acts for:
1. `GET /challenge`.
2. Sign the UTF-8 bytes of `challenge` (64 hex characters) with ML-DSA-87,
   pure, empty context, using the identity's `sign_skey`.
3. Send `auth: {challenge_id, signature}` in the request body, the signature
   as base64 **without** padding.

One proof covers every mutation in the request, so one request writes rows
of one identity. Which identity a table expects is in its requirement (for
example: the sender for `dialog_messages`, the issuer for `vouch_tokens`).
Cookies play no part.

A successful response also carries the next challenge in `x-challenge-id` /
`x-challenge`; those headers are not exposed to cross-origin pages, which
request a challenge each time.

## Writing rows

```json
POST /electric/v1/ingest
{
  "auth": { "challenge_id": "…", "signature": "<base64, unpadded>" },
  "mutations": [
    { "type": "insert", "modified": { "user_hash": "u_…", "…": "…" },
      "syncMetadata": { "relation": "user_cards" } },
    { "type": "update", "original": { "user_hash": "u_…" }, "changes": { "…": "…" },
      "syncMetadata": { "relation": "user_cards" } }
  ]
}
```

- `relation` is the table name. An update names the primary key in
  `original` and sends the changed and signed fields in `changes`.
- Fields ending in `_pkey`, `_cert`, `_b64` and `_hashes` are base64, padded or
  not. Hashes are their prefixed hex strings (`u_…`, `di_…`).
- Every row carries `sign_b64`: ML-DSA-87 over the canonical payload of all
  its other fields except `sign_hash` (`02_integrity.md`). The payload encodes
  base64 fields **padded**.
- `sign_hash` (`"<prefix>_" + hex(SHA3-512(sign_b64))`) is sent for
  `dialog_messages` and `origins`; other tables derive it.
- `owner_timestamp` is an integer that grows with every write of the same
  row; an update with an equal or smaller value is refused.
- There is no delete: a removed row is an update with `deleted_flag = true`.
- Write a new identity's `user_cards` row alone, in its own request, before
  anything else of it.

Test a signer against `test/fixtures/pq_conformance_vectors.json`.

### Responses

| `/ingest` | Meaning |
|---|---|
| `200 {txid}` | Written |
| `400` | Malformed request, unknown table, a row that fails a check (plain-text reason) |
| `401 {error}` | Challenge invalid, expired or reused; signature does not verify |
| `403 {"error": "not_in_trust_chain", "max_depth": N}` | The access mode requires a vouch chain this identity lacks |
| `409 {status: "exists", conflicted}` | The row exists already |
| `409 {"error": "pub_key_taken"}` | Another card holds this key |
| `422 {"error": "validation_failed", details}` | Field validation |
| `503 {"error": "database_timeout"}` with `retry-after` | Retry later |

`/ingest_each` answers `{results: [{index, status, …}]}`, with `status`
`ok`, `exists` or `error` per row; the response is `200` if all succeeded,
`403` if every failed row was refused by the gate, `422` otherwise. Decide per
row by its `error`.

A `not_in_trust_chain` write is not invalid: it succeeds once the identity
is vouched for. Keep it and retry after approval.

## Reading

`GET /electric/v1/shapes?table=<table>&offset=-1&where=<condition>` is the
Electric HTTP API: a first request returns rows and `electric-handle` /
`electric-offset` headers; `&live=true&handle=…&offset=…` long-polls for
changes.

- Any table of the server's registry is readable, with any `where`.
- Binary columns come back as base64 **without** padding. Pad them before
  verifying a signature.
- Access mode `trust`: a read without a session gets
  `401 {"error": "read_session_required", "shape": S}`. Open one with
  `POST /read_session {user_hash, shape: S, challenge_id, signature}`, send
  `Authorization: Bearer <token>` on every read of that shape, and renew when
  under 60 s of its 300 remain or on another `401`. `user_cards` and
  `vouch_tokens` never need one. Details:
  [reqs/pq_access_gating.done.md](reqs/pq_access_gating.done.md).

## Access modes and scopes

A server runs in `open`, `guarded` (writes need a vouch chain from the server
owner) or `trust` (reads too). No endpoint reports the mode: a client learns
it from `403` and `401` answers. Scopes name the server by `device_id` from
`/device_identity`: `device.<device_id>.storage.write.<shape>` and
`.storage.read.<shape>` ([reqs/pq_vouch_tokens.in_progress.md](reqs/pq_vouch_tokens.in_progress.md)).
