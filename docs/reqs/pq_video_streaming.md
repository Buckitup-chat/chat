# Client-Side Video Streaming

Zero-knowledge video playback via a Service Worker that intercepts native `<video>` range requests, fetches encrypted chunks from the Electric Shape API, decrypts them client-side (AES-256-GCM), and returns plaintext as HTTP `206 Partial Content` responses. The server stores and serves only opaque encrypted chunks — it never sees plaintext video data.

## 1. Problem

Videos in the PQ system are encrypted as 4 MB AES-256-GCM chunks stored in PostgreSQL (see [pq_files.md](pq_files.md)). The file sandbox can download all chunks, decrypt them client-side, and reassemble into a Blob — but this requires downloading the **entire** video before playback starts. A 200 MB video means a multi-minute wait with no playback.

The old server-side decryption path (Blowfish via `FileController` with HTTP Range requests) enables progressive playback but violates the zero-knowledge goal: the server decrypts chunks and sees plaintext.

We need progressive video playback where the browser fetches, decrypts, and plays chunks on-the-fly — with native seeking support.

## 2. Goals and Non-Goals

**Goals:**
- Progressive playback — start playing after the first chunk is decrypted, not after the entire file downloads
- Native seeking — user can jump to arbitrary positions via the browser's built-in range request mechanism
- Zero-knowledge — server stores and serves only opaque encrypted chunks
- Reuse existing `decryptChunk()` logic (AES-256-GCM via Web Crypto API)
- Work within the file sandbox as a "Play Video" action alongside existing "View Image" and "Download"

**Non-goals:**
- Adaptive bitrate streaming (ABR/HLS/DASH)
- Server-side transcoding or transmuxing (violates zero-knowledge)
- DRM (access control is handled by the content type being inside encrypted message content)
- Live streaming (this covers stored video files only)

## 3. Architecture Overview

```
<video src="/encrypted-video/{sessionId}">
        │
        │  native Range request (bytes=start-end)
        ▼
┌─────────────────────────────────────────┐
│  Service Worker (video-sw.js)           │
│                                         │
│  1. Parse Range header                  │
│  2. Map byte range → chunk indexes      │
│  3. Fetch chunks from Electric API      │
│  4. Decrypt (AES-256-GCM)              │
│  5. Slice to exact byte range           │
│  6. Return 206 Partial Content          │
└─────────────────────────────────────────┘
        │
        ▼
  Electric Shape API (encrypted 4 MB chunks in PostgreSQL)
```

Each encrypted chunk is independently decryptable — the 12-byte nonce is prepended to the ciphertext (see [§2 Chunk Encryption in pq_files.md](pq_files.md#2-chunk-encryption)). The browser's native `<video>` media stack handles all buffering, codec detection, and seeking via standard HTTP range requests.

**Metadata source:** the [`"video"` content type](../electric/pq_data_layer/07_content_polymorphism.md#video) provides `file_id`, `enc_secret_b64`, `mime_type`, `size`, and visual preview data (`width_aspect`, `height_aspect`, `thumb_hash_b64`).

## 4. Why Not MSE

We initially implemented video streaming using MediaSource Extensions (MSE) with mp4box.js for container parsing. This approach required ~500 lines of complex state management:

- MP4 container parsing and codec detection via mp4box.js
- Manual SourceBuffer management with ordered appends
- Backpressure logic, QuotaExceededError recovery, and buffer eviction
- Custom seeking (estimate chunk, abort, flush, re-append)
- Per-track initialization segment splitting
- No native seeking — sequential-only playback

MSE proved too fragile: QuotaExceeded errors on longer videos, codec detection edge cases, moov-at-end handling, and iOS requiring `ManagedMediaSource`. The Service Worker approach eliminates all of this by delegating media handling to the browser's native `<video>` implementation.

## 5. Service Worker Pipeline

### 5.1 Session Registration

The main page registers a video session with the SW via `postMessage`:

```javascript
navigator.serviceWorker.controller.postMessage({
  type: 'register',
  sessionId,          // crypto.randomUUID()
  fileId,             // "f_" + UUID
  encSecret,          // hex-encoded 32-byte key
  chunkCount,         // from files manifest
  totalSize,          // plaintext total size
  chunkSize,          // 4194304 (4 MB)
  baseUrl             // Electric API base URL
});

videoElement.src = `/encrypted-video/${sessionId}`;
```

### 5.2 Range Request Handling

The SW intercepts fetches to `/encrypted-video/{sessionId}`:

1. **Parse Range header** — `bytes=start-end` (or open-ended `bytes=start-`)
2. **Map to chunks** — `startChunk = floor(start / chunkSize)`, `endChunk = floor(end / chunkSize)`
3. **Cap response** — max 4 chunks (16 MB) per response to avoid fetching the entire file
4. **Fetch + decrypt** each needed chunk from Electric Shape API
5. **Slice** the decrypted data to the exact requested byte range
6. **Return** `206 Partial Content` with `Content-Range: bytes start-end/totalSize`

**Initial request (no Range header):** Return `200 OK` with `Content-Length: totalSize`, `Accept-Ranges: bytes`, and the first chunk as body. The browser detects range support and switches to `206` requests.

### 5.3 Byte-to-Chunk Mapping

```
startChunk = Math.floor(startByte / chunkSize)
endChunk   = Math.floor(Math.min(endByte, totalSize - 1) / chunkSize)
offsetInFirstChunk = startByte - (startChunk * chunkSize)
```

The last chunk may be smaller than `chunkSize`: its plaintext size is `totalSize - (chunkCount - 1) * chunkSize`.

### 5.4 Chunk Cache (LRU)

Decrypted chunks are cached in-memory (max 8 chunks = 32 MB) with LRU eviction. This avoids re-fetching when the browser re-requests overlapping ranges or the user seeks back.

On session `unregister`, all cached chunks for that session are purged.

## 6. Chunk Fetch Strategy

Individual chunks fetched via Electric Shape API:

```
GET /electric/v1/shapes?table=file_chunks&where=file_id='<id>' AND chunk_index=<n>&offset=-1
```

The SW paginates through Electric's offset/handle mechanism until `up-to-date` is received, then extracts `data_b64` from the first matching row.

## 7. Integration

### 7.1 Existing Crypto

The SW contains an inline copy of `decryptChunk()` — identical logic to `assets/js/file-sandbox/crypto.js`. It extracts the 12-byte nonce, decrypts with AES-256-GCM via `crypto.subtle`, and returns plaintext bytes. Service Workers have full access to the Web Crypto API.

### 7.2 Video Content Type Metadata

The [`"video"` content type](../electric/pq_data_layer/07_content_polymorphism.md#video) provides all fields needed:

| Position | Field | Used for |
|---|---|---|
| 0–1 | width_aspect, height_aspect | Video element sizing |
| 2 | thumb_hash_b64 | Preview placeholder while loading |
| 4 | size | `totalSize` for Content-Length / Content-Range |
| 5 | mime_type | Content-Type header in SW response |
| 7 | file_id | Chunk fetch queries |
| 8 | enc_secret_b64 | Decryption key |

### 7.3 ThumbHash Preview

While the first chunk is being fetched and decrypted, render the [ThumbHash](https://evanw.github.io/thumbhash/) as a blurred placeholder in the video element's poster or a background `<canvas>`. This gives immediate visual feedback with the correct aspect ratio.

### 7.4 File Sandbox

The "Play Video" button in the file sandbox:

1. User enters `file_id` and `enc_secret` (same as download)
2. Click "Play Video"
3. Register SW session with file metadata
4. Set `video.src = /encrypted-video/{sessionId}`
5. Browser issues range requests, SW decrypts on the fly
6. Native seeking works immediately

## 8. Security

### 8.1 Key Hygiene

- **Never log keys.** `enc_secret` and derived `CryptoKey` objects must not appear in `console.log`, error reporters, or analytics.
- **SecureContext only.** Web Crypto API requires HTTPS or localhost. The streaming pipeline will not function on plain HTTP.
- **Session isolation.** Each video session uses a random UUID in its URL — other tabs/pages cannot guess it.
- **Key lifetime.** The encryption secret lives only in the SW's `sessions` Map. On `unregister`, the session (and key reference) is deleted.

### 8.2 Decryption Error Handling

AES-256-GCM decryption throws if the authentication tag does not verify. On decryption failure, the SW returns a 500 error response — the browser surfaces this as a media error. Never serve partial or unverified data.

## 9. Fallback

For browsers without Service Worker support (negligible today):

1. Fall back to full-download approach: fetch all chunks, decrypt, reassemble as Blob
2. Create blob URL: `URL.createObjectURL(blob)`
3. Set as `<video>` source: `videoElement.src = blobURL`
4. Show progress bar during download/decryption

## 10. Browser Compatibility

| Feature | Chrome | Firefox | Safari (desktop) | Safari (iOS) |
|---|---|---|---|---|
| Service Workers | 40+ | 44+ | 11.1+ | 11.3+ |
| Web Crypto AES-GCM | 37+ | 34+ | 11+ | 11+ |
| Range requests on `<video>` | All | All | All | All |

The SW approach has **better** iOS support than MSE — iOS has always supported native `<video>` range requests but only gained MSE support in iOS 17 via `ManagedMediaSource`.

## 11. Limitations and Trade-offs

| Limitation | Impact | Mitigation |
|---|---|---|
| 4 MB chunk size | ~2–6 sec seeking granularity at chunk boundaries | Browser handles sub-chunk seeking via keyframes in already-fetched data |
| First-frame latency | Full 4 MB chunk must be fetched + decrypted before any playback | ThumbHash preview during load; first chunk cached after initial play |
| AES-GCM full-chunk decrypt | Cannot decrypt partial chunk (auth tag covers entire chunk) | 4 MB decrypts in ~5 ms on modern hardware; capped at 4 chunks per response |
| No ABR | Single quality level | User gets whatever quality was uploaded |
| SW registration latency | First play may wait for SW activation | `skipWaiting()` + `clients.claim()` minimize delay |

## 12. Implementation Files

| File | Role |
|---|---|
| `priv/static/video-sw.js` | Standalone Service Worker (not Vite-bundled) |
| `assets/js/file-sandbox/video-sw-streamer.js` | Client shim — registers SW, manages sessions |
| `assets/js/file-sandbox/crypto.js` | Reference for decryption logic (duplicated inline in SW) |

## 13. Resolved Questions

- **MSE vs Service Worker:** Service Worker chosen — MSE was too fragile (QuotaExceeded, codec detection, buffer management complexity). SW delegates all media handling to the browser's native stack.
- **Crypto algorithm:** AES-256-GCM per [pq_files.md §2](pq_files.md#2-chunk-encryption)
- **Chunk size:** 4 MB per [pq_files.md §12](pq_files.md#12-chunk-size-decision)
- **Nonce handling:** each chunk carries its own random nonce prepended to the ciphertext; `decryptChunk()` extracts it transparently
- **Seeking:** native — the browser issues range requests, SW maps bytes to chunks
- **iOS:** native `<video>` + SW works on iOS 11.3+ (no ManagedMediaSource needed)
- **Blowfish migration:** the old server-side decryption path (Blowfish CFB64 via `FileController`) remains for backward compatibility with pre-PQ files. New PQ files use client-side AES-256-GCM exclusively.
