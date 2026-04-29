# Content Polymorphism

> Status: **partial design** — JSON envelope shape defined; out-of-band files use encrypted chunks in PostgreSQL ([pq_files.md](../../reqs/pq_files.md)).

## Problem

A message's payload can be text, image, video, audio, or file. These differ in size by orders of magnitude (a few bytes for text, potentially hundreds of MB for video) and in how they are consumed (inline render vs. stream vs. download). The data layer needs one row shape that accommodates all of them without inflating the hot path for text, without giving up the integrity guarantees of [02_integrity.md](./02_integrity.md), and **without leaking the content type to the database in plaintext**.

## Approach

**Single encrypted content blob.** The carrier row (e.g. `dialog_messages.content_b64` — see [pq_dialogs.md §dialog_messages](../../reqs/pq_dialogs.md)) stores `12-byte AES-GCM nonce ‖ ciphertext`. The plaintext is JSON, shaped by convention:

| Plaintext shape                    | Meaning                                                                                                                        |
| ---------------------------------- |--------------------------------------------------------------------------------------------------------------------------------|
| `"some text"` (bare JSON string)   | Plain text                                                                                                                     |
| `[element, ...]` (JSON array)      | Composed message; each element is either a bare string (text) or a compound object (`{"<type>": <value>}`) or nested (`[...]`) |
| `{"<type>": <value>}` (one key)    | Compound content; the key names the type, the value carries the payload                                                        |

Examples:

```json
"hello"
["here is example of composed message", {"inline_image": [16, 9, "some.jpg", ... ]}]
{"image": [16, 9, "filename.jpg", "<inline-base64>"]}
{"file":  ["doc.pdf",1048576, ...]}
{"audio": [4200, ...]}
```

Because the type lives inside the ciphertext, the database (and any peer without the dialog secret) cannot tell whether a row is text, image, or attachment — only its size class.

## Known types

- [`"inline_file"`](#inline_file) — small file, inline base64
- [`"inline_image"`](#inline_image) — small image, inline base64 with aspect ratio and thumbhash
- [`"file"`](#file) — large file, out-of-band encrypted chunks in PostgreSQL

### `"inline_file"`

Small file embedded directly in the message content (base64-encoded). Subject to inline size limits (500 KB soft / 1 MB hard).

```json
{"inline_file": [filename, size, mime_type, creation_unixtime, data_b64]}
```

| Position | Field | Description |
|---|---|---|
| 0 | filename | Original filename |
| 1 | size | Plaintext byte size |
| 2 | mime_type | MIME type |
| 3 | creation_unixtime | Unix seconds of uploaded file creation |
| 4 | data_b64 | File contents in base64 |

### `"inline_image"`

Small image embedded directly in the message content (base64-encoded). Includes aspect ratio and thumbhash for preview rendering before full decode.

```json
{"inline_image": [width_aspect, height_aspect, thumb_hash_b64, filename, size, mime_type, creation_unixtime, data_b64]}
```

| Position | Field | Description |
|---|---|---|
| 0 | width_aspect | Width component of aspect ratio |
| 1 | height_aspect | Height component of aspect ratio |
| 2 | thumb_hash_b64 | [ThumbHash](https://evanw.github.io/thumbhash/) in base64 |
| 3 | filename | Original filename |
| 4 | size | Plaintext byte size |
| 5 | mime_type | MIME type |
| 6 | creation_unixtime | Unix seconds of uploaded file creation |
| 7 | data_b64 | Image contents in base64 |

### `"file"`

Out-of-band file stored as encrypted chunks in PostgreSQL. See [pq_files.md](../../reqs/pq_files.md) for chunk encryption, tables, upload/sync protocols, and GC.

```json
{"file": [name, size, mime_type, creation_unixtime, file_id, enc_secret_b64]}
```

| Position | Field | Description |
|---|---|---|
| 0 | name | Original filename |
| 1 | size | Plaintext byte size |
| 2 | mime_type | MIME type |
| 3 | creation_unixtime | Unix seconds of uploaded file creation |
| 4 | file_id | References `files.file_id` |
| 5 | enc_secret_b64 | AES-256 key for chunk decryption (base64) |

Because this lives inside ciphertext, the database cannot tell whether a row is text or a file attachment. Only dialog members who can decrypt `content_b64` learn the file exists and obtain `enc_secret` to decrypt chunks.

--- 

### Inline vs. out-of-band

For small payloads, the bytes sit inside the JSON value directly (base64-encoded). **Soft limit: 500 KB** for inline objects. **Hard limit: the top-level `content_b64` field must not exceed 1 MB** after encryption.

For large payloads, use the out-of-band `"file"` content type — the JSON value carries a reference (`file_id` + `enc_secret_b64`) and the actual bytes live in encrypted chunks in PostgreSQL (see [pq_files.md](../../reqs/pq_files.md)).

The carrier row's `sign_b64` covers the whole `content_b64` (nonce + ciphertext), so any tampering with the envelope — including embedded references — is detected.

## Deletion

A signed deletion is `deleted_flag = true` plus an empty `content_b64`. The empty plaintext is the explicit tombstone — readers see "deleted" without needing to decrypt content that no longer exists. Out-of-band blobs referenced by superseded versions become eligible for GC under whatever retention policy the storage channel applies.

## Where this touches existing work

- **Carrier row**: [pq_dialogs.md §dialog_messages](../../reqs/pq_dialogs.md) — `content_b64` is the single-blob field.
- **Out-of-band file storage**: [pq_files.md](../../reqs/pq_files.md) — encrypted chunk storage in PostgreSQL for large files; inline content for small payloads.
- **Integrity primitive**: [02_integrity.md](./02_integrity.md) — `content_b64` is one of the signed fields like any other.

## Invariants

- The plaintext JSON object has at most one key — it names the content type. Bare strings are text by convention.
- Content type is never a column on the carrier row; it is only visible after decryption.
- A new content type is a new JSON key, not a schema migration.
- Out-of-band file references (`file_id`, `enc_secret_b64`) inside the envelope are integrity-bound by the carrier row's `sign_b64`; chunk integrity is ensured by `files.chunk_sign_hashes` (see [pq_files.md](../../reqs/pq_files.md)).
- An empty `content_b64` is only valid alongside `deleted_flag = true`.

## Resolved questions

- **Inline size limits**: 500 KB soft limit for inline objects; 1 MB hard limit for the top-level `content_b64` field.
- **Content type registry**: defined in this document (§ Known types). New types are added here as needed.

## Open questions

- Out-of-band file GC: when can chunk data be reclaimed? See [pq_files.md §7](../../reqs/pq_files.md) for the current GC design.
