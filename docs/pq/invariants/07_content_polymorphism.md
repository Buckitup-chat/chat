# Content Polymorphism

> Status: **partial design** — JSON envelope shape defined; out-of-band files use encrypted chunks in PostgreSQL ([pq_files.md](../reqs/files/pq_files.done.md)).

## Problem

A message's payload can be text, image, video, audio, or file. These differ in size by orders of magnitude (a few bytes for text, potentially hundreds of MB for video) and in how they are consumed (inline render vs. stream vs. download). The data layer needs one row shape that accommodates all of them without inflating the hot path for text, without giving up the integrity guarantees of [02_integrity.md](./02_integrity.md), and **without leaking the content type to the database in plaintext**.

## Approach

**Single encrypted content blob.** The carrier row (e.g. `dialog_messages.content_b64` — see [pq_dialogs.done.md §dialog_messages](../reqs/pq_dialogs.done.md)) stores `12-byte AES-GCM nonce ‖ ciphertext`. The plaintext is JSON, shaped by convention:

| Plaintext shape                    | Meaning                                                                                                                        |
| ---------------------------------- |--------------------------------------------------------------------------------------------------------------------------------|
| `"some text"` (bare JSON string)   | Plain text                                                                                                                     |
| `[element, ...]` (JSON array)      | Composed message; each element is either a bare string (text) or a compound object (`{"<type>": <value>}`) or nested (`[...]`) |
| `{"<type>": <value>}` (one key)    | Compound content; the key names the type, the value carries the payload                                                        |

Examples:

```json
"hello"
["here is example of composed message", {"inline_image": [16, 9, "thumbhash...", "some.jpg", ... ]}]
{"inline_image": [16, 9, "thumbhash...", "photo.jpg", 204800, "image/jpeg", 1715000000, "<data_b64>"]}
{"image": [16, 9, "thumbhash...", "photo.jpg", 5242880, "image/jpeg", 1715000000, "f_01964...", "<enc_secret_b64>"]}
{"video": [16, 9, "thumbhash...", "clip.mp4", 52428800, "video/mp4", 1715000000, 127, "f_01964...", "<enc_secret_b64>"]}
{"file":  ["doc.pdf", 1048576, "application/pdf", 1715000000, "f_01964...", "<enc_secret_b64>"]}
```

Because the type lives inside the ciphertext, the database (and any peer without the dialog secret) cannot tell whether a row is text, image, or attachment — only its size class.

## Known types

- [`"inline_file"`](#inline_file) — small file, inline base64
- [`"inline_image"`](#inline_image) — small image, inline base64 with aspect ratio and thumbhash
- [`"file"`](#file) — large file, out-of-band encrypted chunks in PostgreSQL
- [`"image"`](#image) — large image, out-of-band with aspect ratio and thumbhash
- [`"video"`](#video) — video, out-of-band with aspect ratio and thumbhash
- [`"checkpoint"`](#checkpoint) — signed commitment to the dialog's causal history and materialized view
- [`"review_list_key"`](#review_list_key) — the sender's `review_list_password`, shared with a contact
- [`"quote"`](#quote) — a snapshot of a cited message, carried inside the reply
- [`"recovery_share"`](#recovery_share) — one guardian's Shamir share of a community backup, owner → guardian
- [`"recovery_share_return"`](#recovery_share_return) — the same share sent back during a recovery, guardian → owner
- [`"recovery_binding"`](#recovery_binding) — a recovering account's proof that it controls the on-chain candidate

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

Out-of-band file stored as encrypted chunks in PostgreSQL. See [pq_files.md](../reqs/files/pq_files.done.md) for chunk encryption, tables, upload/sync protocols, and GC.

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

### `"image"`

Out-of-band image stored as encrypted chunks in PostgreSQL. Extends the `"file"` type with aspect ratio and thumbhash for preview rendering before chunk download. See [pq_files.md](../reqs/files/pq_files.done.md) for chunk encryption.

```json
{"image": [width_aspect, height_aspect, thumb_hash_b64, name, size, mime_type, creation_unixtime, file_id, enc_secret_b64]}
```

| Position | Field | Description |
|---|---|---|
| 0 | width_aspect | Width component of aspect ratio |
| 1 | height_aspect | Height component of aspect ratio |
| 2 | thumb_hash_b64 | [ThumbHash](https://evanw.github.io/thumbhash/) in base64 |
| 3 | name | Original filename |
| 4 | size | Plaintext byte size |
| 5 | mime_type | MIME type |
| 6 | creation_unixtime | Unix seconds of uploaded file creation |
| 7 | file_id | References `files.file_id` |
| 8 | enc_secret_b64 | AES-256 key for chunk decryption (base64) |

Small images (under the inline size limit) should use [`"inline_image"`](#inline_image) instead. The sender decides: if the image fits inline, embed it; otherwise upload chunks and reference via `"image"`.

### `"video"`

Out-of-band video stored as encrypted chunks in PostgreSQL. Carries aspect ratio, thumbhash (from a representative frame) and duration, so a preview with a duration badge renders before any chunk download. See [pq_files.md](../reqs/files/pq_files.done.md) for chunk encryption.

```json
{"video": [width_aspect, height_aspect, thumb_hash_b64, name, size, mime_type, creation_unixtime, duration_seconds, file_id, enc_secret_b64]}
```

| Position | Field | Description |
|---|---|---|
| 0 | width_aspect | Width component of aspect ratio |
| 1 | height_aspect | Height component of aspect ratio |
| 2 | thumb_hash_b64 | [ThumbHash](https://evanw.github.io/thumbhash/) in base64 — computed from a representative frame |
| 3 | name | Original filename |
| 4 | size | Plaintext byte size |
| 5 | mime_type | MIME type |
| 6 | creation_unixtime | Unix seconds of uploaded file creation |
| 7 | duration_seconds | Playback duration in seconds, rounded to the nearest integer but never below `1` for a measured clip; `0` is reserved for "the sender could not determine it" |
| 8 | file_id | References `files.file_id` |
| 9 | enc_secret_b64 | AES-256 key for chunk decryption (base64) |

Videos are always out-of-band — there is no inline variant.

### `"checkpoint"`

A signed DAG checkpoint: the author attests "my device held this causally complete local
state of the dialog, and under the named reducer it materialized to this view". It rides an
ordinary `dialog_messages` row, so the commitments stay inside the ciphertext (the server
sees a normal message), the row's ML-DSA signature covers them, and the row's `refs_map`
makes the checkpoint a merge event over the attested tails. A checkpoint never claims
global completeness — only what was locally present at signing time.

```json
{"checkpoint": [1, "dialog-state-v1", "dialog-view-tree-v1", "dfr_<hex>", "dvr_<hex>", {"dmsg_...": "dms_...", "...": "..."}, 1788470000]}
```

| Position | Field | Description |
|---|---|---|
| 0 | checkpoint_version | Integer; `1` = SHA3-512 commitments, domains below |
| 1 | reducer_version | Rules that turned events into the view; `dialog-state-v1` = gate-admitted current revisions, tombstones included |
| 2 | tree_version | View-commitment structure; `dialog-view-tree-v1` = compressed binary Merkle trie keyed by `message_id` bytes |
| 3 | frontier_root | `dfr_` + hex SHA3-512 over `"BUCKITUP_DIALOG_FRONTIER_V1"` and the sorted `message_id\|sign_hash` pairs |
| 4 | view_root | `dvr_` + hex root of the view trie; leaves hash `"BUCKITUP_DIALOG_VIEW_LEAF_V1"`, `message_id`, the current revision's `sign_hash` and the deleted flag; inner nodes hash `"BUCKITUP_DIALOG_VIEW_NODE_V1"`, the branching bit index and both children |
| 5 | frontier | Object `{message_id: sign_hash}` — the DAG tails observed at checkpoint time; source of truth, position 3 is its fingerprint |
| 6 | created_at | Unix seconds, informational |

`sign_hash` already commits to a revision's full signed content, so the frontier commits to
the causal history transitively and the view leaf needs no separate content hash. History
and view are separate commitments on purpose: "history grew but the view is identical" is
distinguishable from "the visible conversation changed". Unknown `reducer_version` /
`tree_version` make the view unverifiable for the reader, not the checkpoint invalid.

### `"review_list_key"`

The sender's `review_list_password` — one symmetric key per author that decrypts the `password_b64`
column of every `review_list` row they write, and so opens every review they have written or will
write, regardless of moderation state. See [pq_review_contacts](../reqs/reviews/pq_review_contacts.done.md).

```json
{"review_list_key": [key_b64]}
```

| Position | Field | Description |
|---|---|---|
| 0 | key_b64 | AES-256 key in unpadded base64 |

Nothing new cryptographically: `pq_dialogs` already wraps every message with `sender_msg_key` +
ML-KEM-1024, so the key is protected exactly as any other content. The receiving client stores it as
`peer_user_hash → review_list_password`.

The key never rotates — sending it is irreversible, since a contact who has it keeps access to
everything the sender writes afterwards. Delivery is therefore per-recipient and deliberate, not a
broadcast.


### `"quote"`

A snapshot of a cited message, carried inside the citing message. Used as the
first element of a composed message to express a reply:

```json
[{"quote": ["u_ab12…", "dmsg_01990c…", "dms_4f19…", "Схему пришли до четверга"]}, "Уже в очереди, вечером будет"]
```

```json
{"quote": [author_hash, message_id, sign_hash, snapshot]}
```

| Position | Field | Description |
|---|---|---|
| 0 | author_hash | `user_hash` of the quoted message's author |
| 1 | message_id | `dmsg_<UUID7>` of the quoted message |
| 2 | sign_hash | `dms_`-prefixed revision identity of the exact version cited |
| 3 | snapshot | The cited content **at citation time** — any value from this document (bare string, one-key object, or composed array) |

The snapshot is the load-bearing field. It is frozen when the reply is
authored, so the quote renders even when the original row never replicated to
this peer, was edited afterwards, or was deleted — the reply is
self-contained, and later changes to the original are detectable (the cited
`sign_hash` no longer matches the original's tip) rather than silently
rewriting what the reply appeared to answer.

`(message_id, sign_hash)` pin the exact revision for jump-to-original
navigation; when the pair resolves to nothing locally, the quote still
renders from its snapshot and the client simply offers no jump.

The quoted message's authoring time needs no field of its own:
`message_id` is a UUIDv7 whose first 48 bits are the authoring unix
milliseconds (04_ordering.md), so a client that wants to show "when was
this said" derives it from position 1. A separate timestamp field would
be a second source of truth that could disagree with the id.

Because the snapshot is itself canonical content, quoting a message that
contains a quote nests with no special casing. Clients should bound how much
of the nesting they *render* inline; the wire format itself is unbounded.

A quote is context, not authorship: text inside the snapshot belongs to
`author_hash`, not to the sender of the citing message.

--- 

### `"recovery_share"`

One guardian's Shamir share of the friends' half of an owner's community backup,
sent owner → guardian at issue. Post-quantum in transit for free, for the reasons
in [pq_recovery_shares](../reqs/pq_recovery_shares.proposed.md), which owns the
lifecycle this envelope only names. The way back is
[`"recovery_share_return"`](#recovery_share_return): a different key, because a
client acts on the key, and the holding rules for a share received at issue are
wrong for one received at recovery.

```json
{"recovery_share": ["eip155:11155111:0xe634…/0x9f3c…", 1, 3, 5, "<share_b64>", 1715000000, "4f1c…", 2]}
```

```json
{"recovery_share": [secret_ref, version, threshold, total, share_b64, creation_unixtime, split_id, share_index]}
```

| Position | Field | Description |
|---|---|---|
| 0 | secret_ref | Which secret this share belongs to: `<namespace>/<id>`, e.g. `eip155:<chainId>:<contract>/<keccak256(abi.encode(owner, label))>` |
| 1 | version | Share epoch, the contract's own; supersession rules in [pq_recovery_shares § Dying](../reqs/pq_recovery_shares.proposed.md) |
| 2 | threshold | Shamir shares needed to rebuild the friends' half. Not the contract's approval quorum, which counts guardians |
| 3 | total | Shares generated at this version, issued and spare alike |
| 4 | share_b64 | The Shamir share itself, unpadded base64 |
| 5 | creation_unixtime | Unix seconds at issue |
| 6 | split_id | Which Shamir split this share belongs to; semantics in [pq_recovery_shares § Re-issuing](../reqs/pq_recovery_shares.proposed.md) |
| 7 | share_index | The share's index within the split, 1-based; a guardian may hold more than one |

A `split_proof` field is reserved for the next position: what checks a share
against the split's on-chain commitment once one exists.

`secret_ref` names the deployment as well as the chain, because the id does not:
`keccak256(abi.encode(owner, label))` is the same value on every contract, so two
deployments on one chain produce identical ids for the same owner and label.
Carrying the namespace *inside* the value is also what keeps a frozen position
from assuming an EVM chain forever.

The vault's address is **not** here, deliberately. It is derived from `S`
(`chat-frontend/src/lib/pq/vaultEnvelope.ts`), and that derivation exists so the
server cannot tell a vault row from any other `user_storage` row: reads there are
public and unauthenticated, so an address handed to every guardian turns an
unfindable row into a findable one. A recovering client does not need it either —
by the time it can decrypt the row it holds `threshold` shares, and `S` yields
the address directly.

--- 

### `"recovery_share_return"`

A guardian's share sent back to the recovering owner's temporary account, after
the guardian's own approval has been honoured on chain
([pq_recovery_shares § Returning](../reqs/pq_recovery_shares.proposed.md)). It
carries the round and the recipient the guardian checked, so the release
decision is covered by the guardian's signature — the dialog row's, or the
block's when the share returns as text
([pq_recovery_shares § Manual return](../reqs/pq_recovery_shares.proposed.md)) —
and can be audited later.

```json
{"recovery_share_return": ["eip155:11155111:0xe634…/0x9f3c…", 1, "4f1c…", 3, 5, 2, 2, "0x7a1b…", "<share_b64>", 1715600000]}
```

```json
{"recovery_share_return": [secret_ref, version, split_id, threshold, total, share_index, round, candidate, share_b64, creation_unixtime]}
```

| Position | Field | Description |
|---|---|---|
| 0 | secret_ref | As in `"recovery_share"` |
| 1 | version | The epoch the share was issued at |
| 2 | split_id | As in `"recovery_share"`; the recovering client groups shares by it |
| 3 | threshold | Shamir threshold of the split — the recovering client has no other way to know how many it is waiting for; the contract's `threshold` is the guardian quorum |
| 4 | total | Shares in the split |
| 5 | share_index | As in `"recovery_share"` |
| 6 | round | The contract's `recoveryRound` this release answers |
| 7 | candidate | The recipient address the guardian approved, from the binding it verified |
| 8 | share_b64 | The Shamir share itself, unpadded base64 |
| 9 | creation_unixtime | Unix seconds at release |

--- 

### `"recovery_binding"`

Sent by a recovering owner's temporary account, in the dialog a guardian opened
with it — or as text, when the share will return that way — to prove that the
chat identity the guardian is talking to controls the address it will approve
on chain ([pq_recovery_shares § Returning](../reqs/pq_recovery_shares.proposed.md)).
The signature is EIP-191 by the candidate's key over the UTF-8 string
`"buckitup/recovery-binding/v1\n" || secret_ref || "\n" || user_hash`; the
`user_hash` signed is the sender's own. The guardian checks it against the
dialog peer, and against the word code the owner reads out, which is what says
the peer is the person on the call.

```json
{"recovery_binding": ["eip155:11155111:0xe634…/0x9f3c…", "0x7a1b…", "u_ab12…", "<signature_b64>"]}
```

```json
{"recovery_binding": [secret_ref, candidate, user_hash, signature_b64]}
```

| Position | Field | Description |
|---|---|---|
| 0 | secret_ref | The secret this recovery is for; supplied by the guardian's first message |
| 1 | candidate | The address the temporary account will be elected under |
| 2 | user_hash | The sender's own `user_hash`; must equal the dialog peer's, and is covered by the word code the owner reads out |
| 3 | signature_b64 | EIP-191 signature by `candidate`'s key over the string above, unpadded base64 |

--- 

### Inline vs. out-of-band

For small payloads, the bytes sit inside the JSON value directly (base64-encoded). **Soft limit: 500 KB** for inline objects. **Hard limit: the top-level `content_b64` field must not exceed 1 MB** after encryption.

For large payloads, use an out-of-band content type (`"file"`, `"image"`, or `"video"`) — the JSON value carries a reference (`file_id` + `enc_secret_b64`) and the actual bytes live in encrypted chunks in PostgreSQL (see [pq_files.md](../reqs/files/pq_files.done.md)). The `"image"` and `"video"` types add visual metadata (aspect ratio, thumbhash) so the client can render a placeholder before downloading chunks.

The carrier row's `sign_b64` covers the whole `content_b64` (nonce + ciphertext), so any tampering with the envelope — including embedded references — is detected.

## Deletion

A signed deletion is `deleted_flag = true` plus an empty `content_b64`. The empty plaintext is the explicit tombstone — readers see "deleted" without needing to decrypt content that no longer exists. Out-of-band blobs referenced by superseded versions become eligible for GC under whatever retention policy the storage channel applies.

## Where this touches existing work

- **Carrier row**: [pq_dialogs.done.md §dialog_messages](../reqs/pq_dialogs.done.md) — `content_b64` is the single-blob field.
- **Encryption**: `EnigmaPq.aes_gcm_encrypt/2` and `EnigmaPq.aes_gcm_decrypt/2` (`lib/enigma_pq/enigma_pq.ex`) — produce and consume the `nonce(12) || ciphertext || tag(16)` blob format.
- **Out-of-band file storage**: [pq_files.md](../reqs/files/pq_files.done.md) — encrypted chunk storage in PostgreSQL for large files; inline content for small payloads.
- **Integrity primitive**: [02_integrity.md](./02_integrity.md) — `content_b64` is one of the signed fields like any other.

## Invariants

- The plaintext JSON object has at most one key — it names the content type. Bare strings are text by convention.
- Content type is never a column on the carrier row; it is only visible after decryption.
- A new content type is a new JSON key, not a schema migration.
- **Positional fields are append-only**, and the positions of every type in § Known types are frozen as of this document: a new field goes at the end of its type's array, a layout that must change gets a new type key, and layouts are told apart by key rather than by element count. An insertion rebinds every field after it, and codecs that disagree by one position do not fail — they hand back plausible, wrong values.
- **A decoder accepts arrays longer than the layout it knows** and ignores the trailing elements, rather than keying on an exact element count. Without this the rule above buys nothing: an appended field would break every older reader just as loudly as an insertion, only later.
- Out-of-band file references (`file_id`, `enc_secret_b64`) inside the envelope are integrity-bound by the carrier row's `sign_b64`; chunk integrity is ensured by `files.chunk_sign_hashes` (see [pq_files.md](../reqs/files/pq_files.done.md)).
- An empty `content_b64` is only valid alongside `deleted_flag = true`.

## Resolved questions

- **Inline size limits**: 500 KB soft limit for inline objects; 1 MB hard limit for the top-level `content_b64` field.
- **Content type registry**: defined in this document (§ Known types). New types are added here as needed.

## Open questions

- Out-of-band file GC: when can chunk data be reclaimed? See [pq_files.md §8](../reqs/files/pq_files.done.md) for the current GC design.
