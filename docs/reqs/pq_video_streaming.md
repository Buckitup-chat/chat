# Client-Side Video Streaming

Zero-knowledge video playback via client-side chunk decryption and [MediaSource Extensions](https://developer.mozilla.org/en-US/docs/Web/API/MediaSource) (MSE). The server stores and serves only opaque encrypted chunks — it never sees plaintext video data.

## 1. Problem

Videos in the PQ system are encrypted as 4 MB AES-256-GCM chunks stored in PostgreSQL (see [pq_files.md](pq_files.md)). The file sandbox can download all chunks, decrypt them client-side, and reassemble into a Blob — but this requires downloading the **entire** video before playback starts. A 200 MB video means a multi-minute wait with no playback.

The old server-side decryption path (Blowfish via `FileController` with HTTP Range requests) enables progressive playback but violates the zero-knowledge goal: the server decrypts chunks and sees plaintext.

We need progressive video playback where the browser fetches, decrypts, and plays chunks on-the-fly.

## 2. Goals and Non-Goals

**Goals:**
- Progressive playback — start playing after the first chunk is decrypted, not after the entire file downloads
- Seeking — user can jump to arbitrary positions with reasonable latency
- Zero-knowledge — server stores and serves only opaque encrypted chunks
- Reuse existing `decryptChunk()` from `assets/js/file-sandbox/crypto.js` unchanged
- Work within the file sandbox as a "Play Video" action alongside existing "View Image" and "Download"

**Non-goals:**
- Adaptive bitrate streaming (ABR/HLS/DASH)
- Server-side transcoding or transmuxing (violates zero-knowledge)
- DRM (access control is handled by the content type being inside encrypted message content)
- Live streaming (this covers stored video files only)

## 3. Architecture Overview

```
Electric Shape API   →   decryptChunk()   →   SourceBuffer   →   <video>
  (encrypted 4 MB)        (AES-256-GCM)        (MSE API)         (HTML5)
```

Each encrypted chunk is independently decryptable — the 12-byte nonce is prepended to the ciphertext (see [§2 Chunk Encryption in pq_files.md](pq_files.md#2-chunk-encryption)). There is no dependency between chunks for decryption. This maps naturally to MSE's `appendBuffer()` model: fetch a chunk, decrypt it, append the plaintext to the SourceBuffer.

**Metadata source:** the [`"video"` content type](../electric/pq_data_layer/07_content_polymorphism.md#video) provides `file_id`, `enc_secret_b64`, `mime_type`, `size`, and visual preview data (`width_aspect`, `height_aspect`, `thumb_hash_b64`).

## 4. MSE Pipeline

### 4.1 Initialization

```javascript
const mediaSource = new MediaSource();
videoElement.src = URL.createObjectURL(mediaSource);
await new Promise(resolve =>
  mediaSource.addEventListener('sourceopen', resolve, { once: true })
);
```

On iOS 17+, use `ManagedMediaSource` instead of `MediaSource` (see [§11 Browser Compatibility](#11-browser-compatibility)).

### 4.2 Codec Detection

The browser must know the codec string (e.g. `'video/mp4; codecs="avc1.42E01E,mp4a.40.2"'`) to create a SourceBuffer. Since the video content type carries only `mime_type` (e.g. `"video/mp4"`), the exact codec parameters are parsed from the first decrypted chunk:

1. Fetch and decrypt chunk 0
2. Parse `ftyp` and `moov` atoms to extract codec info
3. Call `MediaSource.isTypeSupported(codecString)` to verify
4. Create SourceBuffer with the detected codec string

If the `moov` atom is not in chunk 0 (moov-at-end MP4), fetch and decrypt the **last chunk** to extract it, then resume sequential streaming from chunk 0 (see [§5.2](#52-standard-mp4--moov-at-end)).

### 4.3 Fetch-Decrypt-Append Loop

```javascript
for (let i = 0; i < chunkCount; i++) {
  const encryptedChunk = await fetchChunk(fileId, i);     // Electric Shape API
  const decrypted = await decryptChunk(encryptedChunk, encSecret);  // AES-256-GCM
  
  if (sourceBuffer.updating) {
    await new Promise(r => sourceBuffer.addEventListener('updateend', r, { once: true }));
  }
  sourceBuffer.appendBuffer(decrypted);
}
mediaSource.endOfStream();
```

`decryptChunk()` is reused directly from `assets/js/file-sandbox/crypto.js` — it extracts the 12-byte nonce, decrypts with AES-256-GCM, and returns plaintext bytes.

### 4.4 Buffer Management

At typical video bitrates (5–15 Mbps), each 4 MB chunk holds approximately 2–6 seconds of video.

- **Buffer ahead:** 3–5 chunks (~12–20 MB). Pause fetching when the buffer extends more than ~20 seconds past the current playback position.
- **Eviction:** when `sourceBuffer.buffered` extends more than 30 seconds behind the playback position, call `sourceBuffer.remove(0, currentTime - 30)` to free memory.
- **Resume:** when the buffer shrinks below 2 chunks ahead of playback, resume fetching.

### 4.5 Seeking

When the user seeks to a target time:

1. **Estimate target chunk index.** If the `moov` sample table was parsed (see [§4.2](#42-codec-detection)), use byte-offset-to-chunk mapping. Otherwise estimate linearly: `targetChunk = floor(seekTime / estimatedDuration * chunkCount)`, where `estimatedDuration = totalSize / estimatedBitrate`.
2. **Abort and flush.** Call `sourceBuffer.abort()`, then `sourceBuffer.remove()` to clear the current buffer.
3. **Fetch, decrypt, and append** starting from the target chunk.
4. **Set `video.currentTime`** to the seek target.

Seeking granularity is limited by the 4 MB chunk size (~2–6 seconds per chunk). The browser will snap to the nearest keyframe within the appended data.

## 5. Container and Codec Considerations

### 5.1 Fragmented MP4 (fMP4)

The ideal format for MSE. Each fragment is self-contained (`moof` + `mdat`), so decrypted chunks can be appended directly to the SourceBuffer after an initialization segment.

### 5.2 Standard MP4 — Moov at End

Standard MP4 has a single `moov` atom describing the entire file. If the uploader did not "fast start" the MP4 (move `moov` before `mdat`), the `moov` atom is at the end of the file.

**Handling:**
1. Fetch and decrypt chunk 0 — parse for `moov`
2. If `moov` not found, fetch and decrypt the **last chunk** (`chunk_count - 1`)
3. Extract `moov` from the last chunk, use it as the initialization segment
4. Stream chunks sequentially from chunk 0 — the `mdat` data follows the `moov` for MSE purposes

This adds one extra chunk fetch for moov-at-end files but avoids downloading the entire video.

### 5.3 No Transmuxing Library

Only natively MSE-compatible formats are streamed (MP4/fMP4 with H.264/AAC). Containers that MSE cannot handle (MKV, AVI, MOV with unsupported codecs) fall back to full download + blob URL (see [§10](#10-fallback)).

### 5.4 Supported Codecs

| Container | Video | Audio | MSE Support |
|---|---|---|---|
| MP4/fMP4 | H.264 (AVC) | AAC | Chrome, Firefox, Safari |
| MP4/fMP4 | H.265 (HEVC) | AAC | Safari only |
| WebM | VP9 | Opus | Chrome, Firefox (not Safari) |

**Primary target:** MP4 with H.264 + AAC — universal MSE support across all major browsers.

## 6. Chunk Fetch Strategy

### 6.1 Single-Chunk Fetch

Fetch individual chunks via Electric Shape API with a WHERE clause:

```
GET /electric/v1/shape?table=file_chunks&where=file_id='<id>' AND chunk_index=<n>
```

### 6.2 Range Fetch for Buffer-Ahead

Fetch multiple chunks in a single shape request:

```
GET /electric/v1/shape?table=file_chunks&where=file_id='<id>' AND chunk_index>=<n> AND chunk_index<<n+k>
```

### 6.3 In-Memory Cache

Keep recently decrypted chunks in a `Map<number, Uint8Array>` keyed by chunk index. This avoids re-fetching and re-decrypting when the user seeks back to an already-played position.

Size-limit the cache (e.g. ~50 MB / ~12 chunks). Evict least-recently-used entries when the limit is exceeded.

## 7. Integration

### 7.1 Existing Crypto

`decryptChunk(blob, encSecret)` in `assets/js/file-sandbox/crypto.js` is used unchanged. It handles nonce extraction and AES-256-GCM decryption via Web Crypto API.

### 7.2 Video Content Type Metadata

The [`"video"` content type](../electric/pq_data_layer/07_content_polymorphism.md#video) provides all fields needed:

| Position | Field | Used for |
|---|---|---|
| 0–1 | width_aspect, height_aspect | Video element sizing |
| 2 | thumb_hash_b64 | Preview placeholder while loading |
| 4 | size | Duration estimation for seeking |
| 5 | mime_type | MSE codec detection starting point |
| 7 | file_id | Chunk fetch queries |
| 8 | enc_secret_b64 | Decryption key |

### 7.3 ThumbHash Preview

While the first chunk is being fetched and decrypted, render the [ThumbHash](https://evanw.github.io/thumbhash/) as a blurred placeholder in the video element's poster or a background `<canvas>`. This gives immediate visual feedback with the correct aspect ratio.

### 7.4 File Sandbox Extension

Add a "Play Video" button alongside "View Image" in the file sandbox download section:

1. User enters `file_id` and `enc_secret` (same as download)
2. Click "Play Video"
3. Show ThumbHash preview with loading spinner
4. Initialize MSE pipeline
5. Fetch first chunk, detect codec, create SourceBuffer
6. Start playback as soon as first chunk is appended
7. Continue fetching/decrypting/appending subsequent chunks in the background

## 8. Performance

### 8.1 Web Worker for Decryption

Decryption on the main thread blocks the UI during `appendBuffer()` waits. Offload `decryptChunk()` to a dedicated Web Worker:

```javascript
// main thread
const cryptoWorker = new Worker('crypto-worker.js');

function decryptInWorker(encryptedChunk, encSecret) {
  return new Promise(resolve => {
    cryptoWorker.postMessage({ chunk: encryptedChunk, key: encSecret });
    cryptoWorker.addEventListener('message', e => resolve(e.data), { once: true });
  });
}

// crypto-worker.js
self.onmessage = async ({ data: { chunk, key } }) => {
  const nonce = chunk.slice(0, 12);
  const ciphertextWithTag = chunk.slice(12);
  const cryptoKey = await crypto.subtle.importKey('raw', key, 'AES-GCM', false, ['decrypt']);
  const plaintext = await crypto.subtle.decrypt(
    { name: 'AES-GCM', iv: nonce, tagLength: 128 }, cryptoKey, ciphertextWithTag
  );
  self.postMessage(new Uint8Array(plaintext));
};
```

AES-GCM via Web Crypto API is hardware-accelerated and runs at 200–2000 MB/s — a 4 MB chunk decrypts in under 5 ms. The worker overhead is primarily about keeping the main thread free for rendering and user interaction, not crypto throughput.

### 8.2 Parallel Chunk Fetch and Decrypt

Fetch and decrypt multiple buffer-ahead chunks concurrently rather than sequentially:

```javascript
const BUFFER_AHEAD = 5;

async function fetchAndDecryptBatch(fileId, encSecret, startIndex, chunkCount) {
  const end = Math.min(startIndex + BUFFER_AHEAD, chunkCount);
  const promises = [];
  for (let i = startIndex; i < end; i++) {
    promises.push(
      fetchChunk(fileId, i).then(enc => decryptInWorker(enc, encSecret))
    );
  }
  return Promise.all(promises);
}
```

Append results to the SourceBuffer sequentially (MSE requires ordered appends), but overlap network fetch with decryption of previous chunks.

## 9. Security

### 9.1 Key Hygiene

- **Never log keys.** `enc_secret` and derived `CryptoKey` objects must not appear in `console.log`, error reporters, or analytics.
- **SecureContext only.** Web Crypto API requires HTTPS or localhost. The streaming pipeline will not function on plain HTTP.
- **Clear key material when done.** Zero out `Uint8Array` key buffers after the streaming session ends:
  ```javascript
  encSecret.fill(0);
  ```
  `CryptoKey` objects are opaque and GC'd automatically.

### 9.2 Decryption Error Handling

AES-256-GCM decryption throws if the authentication tag does not verify. **Never ignore this error** — it indicates either tampering or a wrong key. On decryption failure:

1. Stop the streaming pipeline
2. Surface the error to the user ("decryption failed — file may be corrupted or the key is incorrect")
3. Do not append partial or unverified data to the SourceBuffer

### 9.3 Random Number Generation

All cryptographic randomness (keys, nonces) must use `crypto.getRandomValues()`. Never use `Math.random()` for any cryptographic purpose.

## 10. Fallback

For browsers without MSE support or containers that MSE cannot handle:

1. Fall back to full-download approach: fetch all chunks, decrypt, reassemble as Blob
2. Create blob URL: `URL.createObjectURL(blob)`
3. Set as `<video>` source: `videoElement.src = blobURL`
4. Show progress bar during download/decryption

This is identical to the existing "View Image" approach but with `<video>` instead of `<img>`.

**Fallback triggers:**
- `MediaSource` (or `ManagedMediaSource`) not available
- `isTypeSupported()` returns false for the detected codec
- Unsupported container (MKV, AVI, etc.)

## 11. Browser Compatibility

| Feature | Chrome | Firefox | Safari (desktop) | Safari (iOS) |
|---|---|---|---|---|
| MediaSource API | 23+ | 42+ | 8+ | 17+ (ManagedMediaSource) |
| MSE + fMP4 H.264 | Yes | Yes | Yes | 17+ |
| Web Crypto AES-GCM | 37+ | 34+ | 11+ | 11+ |
| File System API (fallback download) | 86+ | No | No | No |

**iOS:** standard `MediaSource` is not available. iOS 17+ provides [`ManagedMediaSource`](https://developer.apple.com/documentation/webkitjs/managedmediasource) which supports the same API surface. iOS < 17 uses the full-download fallback exclusively.

**Detection:**

```javascript
const MSE = window.ManagedMediaSource || window.MediaSource;
if (!MSE) {
  // fallback to full download + blob URL
}
```

## 12. Limitations and Trade-offs

| Limitation | Impact | Mitigation |
|---|---|---|
| 4 MB chunk size | ~2–6 sec seeking granularity | Browser snaps to nearest keyframe; acceptable for most use cases |
| First-frame latency | Full 4 MB chunk must be fetched + decrypted before any playback | ThumbHash preview during load; start playback immediately after first chunk |
| Moov-at-end MP4 | Extra round-trip to fetch last chunk | One-time cost per video; subsequent chunks stream normally |
| Memory pressure | ~20 MB for 5-chunk buffer | Evict behind playback position; reduce buffer to 2–3 chunks on constrained devices |
| No ABR | Single quality level | User gets whatever quality was uploaded |
| AES-GCM full-chunk decrypt | Cannot decrypt partial chunk (auth tag covers entire chunk) | Each chunk is small enough (4 MB) to decrypt quickly (~5 ms on modern hardware) |

## 13. Open Questions

1. **Electric Shape API latency for single-chunk fetch** — shapes are designed for streaming sets of rows; need to measure overhead of creating a shape per chunk request vs. a dedicated chunk-serving endpoint.

## 14. Resolved Questions

- **Crypto algorithm:** AES-256-GCM per [pq_files.md §2](pq_files.md#2-chunk-encryption)
- **Chunk size:** 4 MB per [pq_files.md §10](pq_files.md#10-chunk-size-decision) (not 1 MB)
- **Nonce handling:** each chunk carries its own random nonce prepended to the ciphertext; `decryptChunk()` in `crypto.js` extracts it transparently
- **Content type schema:** existing [`"video"` array](../electric/pq_data_layer/07_content_polymorphism.md#video) suffices — no `codec_string` field needed (codec parsed from first decrypted chunk)
- **Moov-at-end:** fetch last chunk first to extract moov, then stream from beginning
- **Transmuxing:** no transmuxing library — only natively MSE-compatible formats stream; others fall back to full download + blob URL
- **iOS:** target iOS 17+ via `ManagedMediaSource`; older iOS uses full-download fallback
- **Max file size:** no limit for streaming — buffer management handles any size
- **WASM vs Web Crypto:** AES-GCM via native Web Crypto API (hardware-accelerated, 200–2000 MB/s, zero bundle size) — no WASM or JS crypto libraries needed for decryption
- **Blowfish migration:** the old server-side decryption path (Blowfish CFB64 via `FileController`) remains for backward compatibility with pre-PQ files. New PQ files use client-side AES-256-GCM exclusively. No re-encryption migration is planned — old files continue to be served via the old path
