# Content Polymorphism

> Status: **not yet implemented** — design sketch.

## Problem

A message's payload can be text, image, video, audio, or file. These differ in size by orders of magnitude (a few bytes for text, potentially hundreds of MB for video) and in how they are consumed (inline render vs. stream vs. download). The data layer needs one message row shape that accommodates all of them without inflating the hot path for text, and without giving up the integrity guarantees of [02_integrity.md](./02_integrity.md).

## Approach

**Split content from envelope.** The message row carries a small, signed envelope; the actual bytes live elsewhere, addressed by content hash.

| Field | Role |
|---|---|
| `content_type` | Tag: `:text`, `:image`, `:video`, `:audio`, `:file`. Extensible. |
| `content_hash` | SHA3-512 of the decrypted payload. Identity of the content, independent of transport. |
| `content_inline` | Optional — the full payload, for small items (e.g. text, short audio). Absent for large items. |
| `content_meta` | Small JSON blob: mime, filename, duration, dimensions, encryption params. |
| `sign_b64` | Signs all of the above — tampering with any field, or swapping the payload, is detected. |

For small payloads (bounded, e.g. ≤ some threshold around 10 kB for text), `content_inline` holds the encrypted bytes directly. For large payloads, `content_inline` is null and the client fetches the blob out-of-band by `content_hash` — candidate channels:

1. **User Storage**: reuse the existing 10 MB-per-value key-value store ([pq_user_storage.md](../../reqs/pq_user_storage.md)) with the `content_hash` as the key. Free integrity because storage rows are already signed.
2. **CubDB / on-device file storage**: the existing large-file path (see [upload_files.livemd](../../flows/upload_files.livemd)) for content exceeding User Storage's 10 MB cap.

The message's `content_hash` binds the envelope to whatever blob is eventually fetched — delivery channel is negotiable, integrity is not.

Encryption follows the existing pattern: client-side, opaque to the server. The key is shared via the conversation's secret ([post-quantum-dialog.md §Dialog Secrets](../../reqs/post-quantum-dialog.md)).

## Where this touches existing work

- **Flagged as open**: [post-quantum-dialog.md](../../reqs/post-quantum-dialog.md) — "polymorphic/embedded content".
- **Existing large-file precedent**: [upload_files.livemd](../../flows/upload_files.livemd).
- **Integrity primitive**: [02_integrity.md](./02_integrity.md) — the envelope is a standard signed PQ row.
- **User Storage as a blob channel**: [pq_user_storage.md](../../reqs/pq_user_storage.md) — already has per-user PoP + shape sync.

## Invariants

- `content_hash` is computed over the **decrypted** bytes, so it stays stable across re-encryptions or re-encoding. Peers verify payload integrity after decryption; a mismatch rejects the payload without revealing it to the UI.
- `content_inline` and out-of-band storage are mutually exclusive per row: if `content_inline` is set, the envelope is self-contained.
- `content_type` does not change the envelope shape — any new media type is a new tag value, not a schema migration.

## Open questions

- Threshold for inline vs. out-of-band (1 kB? 10 kB? config?).
- Whether `content_meta` needs its own sub-signing (e.g., for thumbnails generated later).
- Blob lifecycle: when is the backing blob in User Storage allowed to be GC'd? Proposal: only after every peer acks the message is fully archived elsewhere.
- Streaming media (audio/video live) — out of scope for the data layer; likely belongs to a separate WebRTC path ([device_webrtc.md](../../proposal/device_webrtc.md)).
