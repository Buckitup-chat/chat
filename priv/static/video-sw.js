const MAX_CACHED_CHUNKS = 8;
const MAX_RESPONSE_CHUNKS = 4;

const sessions = new Map();
const chunkCache = new Map();
const cacheOrder = [];

self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (e) => e.waitUntil(self.clients.claim()));

self.addEventListener('message', (e) => {
  const { type, sessionId } = e.data;
  if (type === 'register') {
    const encSecretBytes = hexToBytes(e.data.encSecret);
    sessions.set(sessionId, {
      fileId: e.data.fileId,
      encSecretBytes,
      chunkCount: e.data.chunkCount,
      totalSize: e.data.totalSize,
      chunkSize: e.data.chunkSize || 4_194_304,
      baseUrl: e.data.baseUrl
    });
  } else if (type === 'unregister') {
    sessions.delete(sessionId);
    for (const key of [...chunkCache.keys()]) {
      if (key.startsWith(sessionId + ':')) {
        chunkCache.delete(key);
        const idx = cacheOrder.indexOf(key);
        if (idx !== -1) cacheOrder.splice(idx, 1);
      }
    }
  }
});

self.addEventListener('fetch', (event) => {
  const url = new URL(event.request.url);
  const match = url.pathname.match(/^\/encrypted-video\/(.+)$/);
  if (!match) return;

  const sessionId = match[1];
  const session = sessions.get(sessionId);
  if (!session) {
    event.respondWith(new Response('Session not found', { status: 404 }));
    return;
  }

  event.respondWith(handleVideoRequest(event.request, session, sessionId));
});

async function handleVideoRequest(request, session, sessionId) {
  const { totalSize, chunkSize } = session;
  const rangeHeader = request.headers.get('Range');

  let start = 0;
  let end = totalSize - 1;
  let isRange = false;

  if (rangeHeader) {
    const m = rangeHeader.match(/bytes=(\d+)-(\d*)/);
    if (m) {
      start = parseInt(m[1]);
      end = m[2] ? parseInt(m[2]) : totalSize - 1;
      isRange = true;
    }
  }

  end = Math.min(end, totalSize - 1);

  const maxEnd = Math.min(end, start + MAX_RESPONSE_CHUNKS * chunkSize - 1, totalSize - 1);
  end = maxEnd;

  const startChunk = Math.floor(start / chunkSize);
  const endChunk = Math.floor(end / chunkSize);

  const chunks = [];
  for (let i = startChunk; i <= endChunk; i++) {
    chunks.push(await getDecryptedChunk(session, sessionId, i));
  }

  const offsetInFirst = start - startChunk * chunkSize;
  const length = end - start + 1;
  const body = assembleRange(chunks, offsetInFirst, length);

  const headers = {
    'Content-Type': 'video/mp4',
    'Accept-Ranges': 'bytes',
    'Content-Length': String(length)
  };

  if (isRange) {
    headers['Content-Range'] = `bytes ${start}-${end}/${totalSize}`;
    return new Response(body, { status: 206, headers });
  }

  headers['Content-Length'] = String(totalSize);
  return new Response(body, { status: 200, headers });
}

function assembleRange(decryptedChunks, offsetInFirst, totalLength) {
  if (decryptedChunks.length === 1) {
    return decryptedChunks[0].slice(offsetInFirst, offsetInFirst + totalLength);
  }
  const result = new Uint8Array(totalLength);
  let written = 0;
  for (let i = 0; i < decryptedChunks.length; i++) {
    const chunk = decryptedChunks[i];
    const sliceStart = i === 0 ? offsetInFirst : 0;
    const available = chunk.length - sliceStart;
    const needed = totalLength - written;
    const take = Math.min(available, needed);
    result.set(chunk.subarray(sliceStart, sliceStart + take), written);
    written += take;
  }
  return result;
}

async function getDecryptedChunk(session, sessionId, chunkIdx) {
  const key = `${sessionId}:${chunkIdx}`;
  if (chunkCache.has(key)) {
    const idx = cacheOrder.indexOf(key);
    if (idx !== -1) cacheOrder.splice(idx, 1);
    cacheOrder.push(key);
    return chunkCache.get(key);
  }

  const encrypted = await fetchChunkFromElectric(session.baseUrl, session.fileId, chunkIdx);
  const decrypted = await decryptChunk(encrypted, session.encSecretBytes);

  while (cacheOrder.length >= MAX_CACHED_CHUNKS) {
    chunkCache.delete(cacheOrder.shift());
  }
  chunkCache.set(key, decrypted);
  cacheOrder.push(key);
  return decrypted;
}

// --- Electric Shape API fetch ---

async function fetchChunkFromElectric(baseUrl, fileId, chunkIndex) {
  let offset = '-1';
  let handle = null;

  while (true) {
    const url = new URL(`${baseUrl}/electric/v1/shapes`);
    url.searchParams.set('table', 'file_chunks');
    url.searchParams.set('where', `file_id = '${fileId}' AND chunk_index = ${chunkIndex}`);
    url.searchParams.set('offset', offset);
    if (handle) url.searchParams.set('handle', handle);

    const resp = await fetch(url, { cache: 'no-store' });
    if (!resp.ok) throw new Error(`Chunk fetch failed: ${resp.status}`);

    if (!handle) handle = resp.headers.get('electric-handle');
    offset = resp.headers.get('electric-offset') || offset;

    const body = await resp.json();
    if (Array.isArray(body)) {
      for (const entry of body) {
        if (entry.value) return parseChunkData(entry.value.data_b64);
      }
    }

    const isUpToDate = resp.headers.has('electric-up-to-date')
      || body.some(e => e.headers?.control === 'up-to-date');
    if (isUpToDate) break;
  }

  throw new Error(`Chunk ${chunkIndex} not found`);
}

// --- AES-256-GCM decryption ---

async function decryptChunk(blob, encSecretBytes) {
  const nonce = blob.slice(0, 12);
  const ciphertextWithTag = blob.slice(12);
  const key = await crypto.subtle.importKey('raw', encSecretBytes, 'AES-GCM', false, ['decrypt']);
  const plaintext = await crypto.subtle.decrypt(
    { name: 'AES-GCM', iv: nonce, tagLength: 128 }, key, ciphertextWithTag
  );
  return new Uint8Array(plaintext);
}

// --- Data parsing ---

function parseChunkData(raw) {
  if (typeof raw === 'string' && raw.startsWith('\\x')) {
    return hexToBytes(raw.slice(2));
  }
  if (typeof raw === 'string') {
    const padded = raw + '='.repeat((4 - (raw.length % 4)) % 4);
    const binary = atob(padded);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
    return bytes;
  }
  return new Uint8Array(raw);
}

function hexToBytes(hex) {
  if (hex.startsWith('\\x')) hex = hex.slice(2);
  if (hex.startsWith('0x')) hex = hex.slice(2);
  const bytes = new Uint8Array(hex.length / 2);
  for (let i = 0; i < bytes.length; i++) bytes[i] = parseInt(hex.substr(i * 2, 2), 16);
  return bytes;
}
