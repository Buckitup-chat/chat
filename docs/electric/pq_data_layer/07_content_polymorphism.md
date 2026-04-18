# Content Polymorphism

> Status: **partial design** — JSON envelope shape defined; out-of-band blob channel TBD.

## Problem

A message's payload can be text, image, video, audio, or file. These differ in size by orders of magnitude (a few bytes for text, potentially hundreds of MB for video) and in how they are consumed (inline render vs. stream vs. download). The data layer needs one row shape that accommodates all of them without inflating the hot path for text, without giving up the integrity guarantees of [02_integrity.md](./02_integrity.md), and **without leaking the content type to the database in plaintext**.

## Approach

**Single encrypted content blob.** The carrier row (e.g. `dialog_messages.content_b64` — see [pq_dialogs.md §dialog_messages](../../reqs/pq_dialogs.md)) stores `12-byte AES-GCM nonce ‖ ciphertext`. The plaintext is JSON, shaped by convention:

| Plaintext shape                    | Meaning                                                                 |
| ---------------------------------- | ----------------------------------------------------------------------- |
| `"some text"` (bare JSON string)   | Plain text                                                              |
| `{"<type>": <value>}` (one key)    | Compound content; the key names the type, the value carries the payload |

Examples:

```json
"hello"
{"image": [16, 9, "filename.jpg", "<inline-base64>"]}
{"file":  {"name": "doc.pdf", "size": 1048576, "blob_hash": "uss_<hex>"}}
{"audio": {"duration_ms": 4200, "blob_hash": "uss_<hex>"}}
```

Because the type lives inside the ciphertext, the database (and any peer without the dialog secret) cannot tell whether a row is text, image, or attachment — only its size class.

### Inline vs. out-of-band

For small payloads, the bytes sit inside the JSON value directly (base64-encoded — bounded by some threshold, e.g. ≤ ~10 kB so a hot text row stays cheap to fetch).

For large payloads, the JSON value carries a `blob_hash` reference and the actual bytes live elsewhere:

1. **User Storage** ([pq_user_storage.md](../../reqs/pq_user_storage.md)) — reuse the 10 MB-per-value key-value store keyed by content hash. Free integrity (storage rows are already signed).
2. **CubDB / on-device file storage** — for content exceeding User Storage's 10 MB cap; existing large-file path (see [upload_files.livemd](../../flows/upload_files.livemd)).

The carrier row's `sign_b64` covers the whole `content_b64` (nonce + ciphertext), so any tampering with the envelope — including the embedded `blob_hash` — is detected. The blob's own integrity is ensured by hash addressing.

## Deletion

A signed deletion is `deleted_flag = true` plus an empty `content_b64`. The empty plaintext is the explicit tombstone — readers see "deleted" without needing to decrypt content that no longer exists. Out-of-band blobs referenced by superseded versions become eligible for GC under whatever retention policy the storage channel applies.

## Where this touches existing work

- **Carrier row**: [pq_dialogs.md §dialog_messages](../../reqs/pq_dialogs.md) — `content_b64` is the single-blob field.
- **Existing large-file precedent**: [upload_files.livemd](../../flows/upload_files.livemd).
- **Integrity primitive**: [02_integrity.md](./02_integrity.md) — `content_b64` is one of the signed fields like any other.
- **User Storage as a blob channel**: [pq_user_storage.md](../../reqs/pq_user_storage.md).

## Invariants

- The plaintext JSON object has at most one key — it names the content type. Bare strings are text by convention.
- Content type is never a column on the carrier row; it is only visible after decryption.
- A new content type is a new JSON key, not a schema migration.
- `blob_hash` references inside the envelope are integrity-bound by the carrier row's `sign_b64` (envelope tamper) and by hash addressing (blob tamper).
- An empty `content_b64` is only valid alongside `deleted_flag = true`.

## Open questions

- Threshold for inline vs. out-of-band JSON-embedded bytes (1 kB? 10 kB? config?).
- Registry of compound type keys (`image`, `video`, `audio`, `file`, `location`, `quote`, ...) and their canonical value shapes (positional array vs. named object).
- Blob lifecycle: when is the backing blob in User Storage allowed to be GC'd? Proposal: only after every peer acks the message is fully archived elsewhere.
- Streaming media (audio/video live) — out of scope for the data layer; likely belongs to a separate WebRTC path ([device_webrtc.md](../../proposal/device_webrtc.md)).
