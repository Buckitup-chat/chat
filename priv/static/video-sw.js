const MAX_CACHED_CHUNKS = 8;
const MAX_RESPONSE_CHUNKS = 4;
const RETRY_ATTEMPTS = 3;
const RETRY_BASE_DELAY_MS = 500;

const sessions = new Map();
const chunkCache = new Map();
const cacheOrder = [];

// --- IndexedDB session persistence (survives SW termination/restart) ---

const DB_NAME = 'video-sw-sessions';
const STORE_NAME = 'sessions';
let dbPromise;

function openDB() {
  if (!dbPromise) {
    dbPromise = new Promise((resolve, reject) => {
      const req = indexedDB.open(DB_NAME, 1);
      req.onupgradeneeded = () => req.result.createObjectStore(STORE_NAME);
      req.onsuccess = () => resolve(req.result);
      req.onerror = () => { dbPromise = null; reject(req.error); };
    });
  }
  return dbPromise;
}

async function dbPut(sessionId, data) {
  const db = await openDB();
  return new Promise((resolve, reject) => {
    const tx = db.transaction(STORE_NAME, 'readwrite');
    tx.objectStore(STORE_NAME).put(data, sessionId);
    tx.oncomplete = resolve;
    tx.onerror = () => reject(tx.error);
  });
}

async function dbGet(sessionId) {
  const db = await openDB();
  return new Promise((resolve, reject) => {
    const tx = db.transaction(STORE_NAME, 'readonly');
    const req = tx.objectStore(STORE_NAME).get(sessionId);
    req.onsuccess = () => resolve(req.result || null);
    req.onerror = () => reject(req.error);
  });
}

async function dbDelete(sessionId) {
  const db = await openDB();
  return new Promise((resolve, reject) => {
    const tx = db.transaction(STORE_NAME, 'readwrite');
    tx.objectStore(STORE_NAME).delete(sessionId);
    tx.oncomplete = resolve;
    tx.onerror = () => reject(tx.error);
  });
}

async function getSession(sessionId) {
  const session = sessions.get(sessionId);
  if (session) return session;
  try {
    const data = await dbGet(sessionId);
    if (data) {
      sessions.set(sessionId, data);
      return data;
    }
  } catch {}
  return null;
}

// --- SW lifecycle ---

self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (e) => e.waitUntil(self.clients.claim()));

// --- Session management ---

self.addEventListener('message', (e) => {
  const { type, sessionId } = e.data;
  if (type === 'register') {
    const encSecretBytes = hexToBytes(e.data.encSecret);
    const session = {
      fileId: e.data.fileId,
      encSecretBytes,
      chunkCount: e.data.chunkCount,
      totalSize: e.data.totalSize,
      chunkSize: e.data.chunkSize || 4_194_304,
      baseUrl: e.data.baseUrl
    };
    sessions.set(sessionId, session);
    dbPut(sessionId, session).catch(() => {});
  } else if (type === 'unregister') {
    sessions.delete(sessionId);
    dbDelete(sessionId).catch(() => {});
    for (const key of [...chunkCache.keys()]) {
      if (key.startsWith(sessionId + ':')) {
        chunkCache.delete(key);
        const idx = cacheOrder.indexOf(key);
        if (idx !== -1) cacheOrder.splice(idx, 1);
      }
    }
  }
});

// --- Fetch interception ---

self.addEventListener('fetch', (event) => {
  const url = new URL(event.request.url);
  const match = url.pathname.match(/^\/encrypted-video\/(.+)$/);
  if (!match) return;
  event.respondWith(handleFetch(match[1], event.request));
});

async function handleFetch(sessionId, request) {
  try {
    const session = await getSession(sessionId);
    if (!session) return new Response('Session not found', { status: 404 });
    return await handleVideoRequest(request, session, sessionId);
  } catch (err) {
    return new Response(err.message || 'Internal error', { status: 500 });
  }
}

async function handleVideoRequest(request, session, sessionId) {
  const { totalSize, chunkSize, chunkCount } = session;
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

  if (start >= totalSize) {
    return new Response(null, {
      status: 416,
      headers: { 'Content-Range': `bytes */${totalSize}` }
    });
  }

  end = Math.min(end, totalSize - 1);

  const headers = {
    'Content-Type': 'video/mp4',
    'Accept-Ranges': 'bytes'
  };

  if (isRange) {
    end = Math.min(end, start + MAX_RESPONSE_CHUNKS * chunkSize - 1, totalSize - 1);
    const length = end - start + 1;

    const startChunk = Math.floor(start / chunkSize);
    const endChunk = Math.floor(end / chunkSize);

    const chunks = [];
    for (let i = startChunk; i <= endChunk; i++) {
      chunks.push(await getDecryptedChunk(session, sessionId, i));
    }

    const offsetInFirst = start - startChunk * chunkSize;
    const body = assembleRange(chunks, offsetInFirst, length);

    headers['Content-Length'] = String(length);
    headers['Content-Range'] = `bytes ${start}-${end}/${totalSize}`;
    return new Response(body, { status: 206, headers });
  }

  // Non-range: stream entire file progressively via ReadableStream
  let chunkIdx = 0;
  const stream = new ReadableStream({
    async pull(controller) {
      if (chunkIdx >= chunkCount) {
        controller.close();
        return;
      }
      try {
        const chunk = await getDecryptedChunk(session, sessionId, chunkIdx);
        controller.enqueue(chunk);
        chunkIdx++;
      } catch (err) {
        controller.error(err);
      }
    }
  });

  headers['Content-Length'] = String(totalSize);
  return new Response(stream, { status: 200, headers });
}

// --- Chunk assembly ---

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

// --- Chunk fetching with cache and retry ---

async function getDecryptedChunk(session, sessionId, chunkIdx) {
  const key = `${sessionId}:${chunkIdx}`;
  if (chunkCache.has(key)) {
    const idx = cacheOrder.indexOf(key);
    if (idx !== -1) cacheOrder.splice(idx, 1);
    cacheOrder.push(key);
    return chunkCache.get(key);
  }

  const encrypted = await fetchChunkWithRetry(session.baseUrl, session.fileId, chunkIdx);
  const decrypted = await decryptChunk(encrypted, session.encSecretBytes);

  while (cacheOrder.length >= MAX_CACHED_CHUNKS) {
    chunkCache.delete(cacheOrder.shift());
  }
  chunkCache.set(key, decrypted);
  cacheOrder.push(key);
  return decrypted;
}

async function fetchChunkWithRetry(baseUrl, fileId, chunkIndex) {
  const url = `${baseUrl}/electric/v1/file_chunk/${fileId}/${chunkIndex}`;
  let lastError;

  for (let attempt = 0; attempt < RETRY_ATTEMPTS; attempt++) {
    try {
      const resp = await fetch(url, { cache: 'no-store' });
      if (resp.status === 404) throw new Error(`Chunk ${chunkIndex} not found`);
      if (!resp.ok) throw new Error(`Chunk fetch failed: ${resp.status}`);
      return new Uint8Array(await resp.arrayBuffer());
    } catch (err) {
      lastError = err;
      if (err.message.includes('not found')) throw err;
      if (attempt < RETRY_ATTEMPTS - 1) {
        await new Promise(r => setTimeout(r, RETRY_BASE_DELAY_MS * (attempt + 1)));
      }
    }
  }
  throw lastError;
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

function hexToBytes(hex) {
  if (hex.startsWith('\\x')) hex = hex.slice(2);
  if (hex.startsWith('0x')) hex = hex.slice(2);
  const bytes = new Uint8Array(hex.length / 2);
  for (let i = 0; i < bytes.length; i++) bytes[i] = parseInt(hex.substr(i * 2, 2), 16);
  return bytes;
}
