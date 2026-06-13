import { signMlDsa87, uint8ToBase64Unpadded } from './crypto.js';

const textEncoder = new TextEncoder();

function applyShapeLog(rowMap, entries) {
  for (const entry of entries) {
    if (!entry.key) continue;
    if (entry.headers?.operation === 'delete') {
      rowMap.delete(entry.key);
    } else if (entry.value) {
      const existing = rowMap.get(entry.key);
      rowMap.set(entry.key, existing ? { ...existing, ...entry.value } : entry.value);
    }
  }
}

export async function getChallenge(baseUrl) {
  const resp = await fetch(`${baseUrl}/electric/v1/challenge`, {
    headers: { 'Accept': 'application/json' }
  });
  if (!resp.ok) throw new Error(`Challenge request failed: ${resp.status}`);
  return resp.json();
}

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

const INGEST_TIMEOUT_MS = 50_000;

// Statuses worth retrying: backpressure (429/503 from the ingest throttle),
// expired challenge (401 — a fresh one is fetched on the next attempt), and
// transient server/proxy errors. 4xx like 400/403/409/422 are permanent.
function isRetryableStatus(status) {
  return status === 401 || status === 408 || status === 425 ||
    status === 429 || status === 500 || status === 502 ||
    status === 503 || status === 504;
}

function isDuplicateKeyError(body) {
  return body?.error === 'validation_failed' &&
    Array.isArray(body?.details?.file_id) &&
    body.details.file_id.some(msg => /already been taken/i.test(msg));
}

// Honor a server Retry-After header (seconds) when present; otherwise use
// exponential backoff with jitter, capped so a stuck upload still progresses.
function retryDelayMs(resp, attempt) {
  const header = resp && resp.headers && resp.headers.get('retry-after');
  const retryAfter = header ? parseInt(header, 10) : NaN;
  if (Number.isFinite(retryAfter) && retryAfter >= 0) return retryAfter * 1000;
  return backoffMs(attempt);
}

function backoffMs(attempt) {
  const base = Math.min(8000, 250 * 2 ** (attempt - 1));
  return base + Math.floor(Math.random() * 250);
}

/**
 * POST mutations to the ingest endpoint, fetching a fresh single-use challenge
 * for each attempt. Retries on backpressure (429/503), challenge expiry (401),
 * transient 5xx, and network errors with exponential backoff (honoring
 * Retry-After). Aborts the POST after 50s so a slow upload doesn't outlive the
 * server-side challenge TTL (60s). Throws on permanent errors or once
 * `maxAttempts` is exhausted.
 */
function extractChallenge(resp) {
  const id = resp.headers.get('x-challenge-id');
  const challenge = resp.headers.get('x-challenge');
  if (id && challenge) return { challenge_id: id, challenge };
  return null;
}

export async function ingest(baseUrl, mutations, signSkey, logger, opts = {}) {
  const maxAttempts = opts.maxAttempts ?? 6;
  const duplicateIsOk = opts.duplicateIsSuccess ?? false;
  const timing = { challenge_ms: 0, challenge_sign_ms: 0, post_ms: 0, attempts: 0 };
  let prefetched = opts.challenge ?? null;
  let lastError;

  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    timing.attempts = attempt;
    try {
      let challengeResp;
      const t0 = performance.now();
      if (prefetched) {
        challengeResp = prefetched;
        prefetched = null;
      } else {
        challengeResp = await getChallenge(baseUrl);
        if (logger) logger('GET', `${baseUrl}/electric/v1/challenge`, null, challengeResp, 200);
      }
      const t1 = performance.now();

      const challengeBytes = textEncoder.encode(challengeResp.challenge);
      const signature = signMlDsa87(challengeBytes, signSkey);
      const signatureB64 = uint8ToBase64Unpadded(signature);
      const t2 = performance.now();

      const payload = {
        mutations,
        auth: {
          challenge_id: challengeResp.challenge_id,
          signature: signatureB64
        }
      };

      const abort = new AbortController();
      const timer = setTimeout(() => abort.abort(), INGEST_TIMEOUT_MS);

      const resp = await fetch(`${baseUrl}/electric/v1/ingest`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Accept': 'application/json' },
        body: JSON.stringify(payload),
        signal: abort.signal
      });
      clearTimeout(timer);
      const t3 = performance.now();

      timing.challenge_ms = t1 - t0;
      timing.challenge_sign_ms = t2 - t1;
      timing.post_ms = t3 - t2;

      const nextChallenge = extractChallenge(resp);
      const body = await resp.json().catch(() => ({ error: 'unparseable response' }));
      if (logger) logger('POST', `${baseUrl}/electric/v1/ingest`, payload, body, resp.status);

      if (resp.ok) return { ...body, _timing: timing, _nextChallenge: nextChallenge };

      if (resp.status === 422 && duplicateIsOk && isDuplicateKeyError(body))
        return { ...body, _timing: timing, _nextChallenge: nextChallenge };

      const httpError = new Error(`Ingest failed (${resp.status}): ${JSON.stringify(body)}`);
      if (!isRetryableStatus(resp.status)) {
        httpError.permanent = true;
        throw httpError;
      }

      lastError = httpError;
      if (attempt === maxAttempts) throw httpError;
      await sleep(retryDelayMs(resp, attempt));
    } catch (e) {
      if (e.permanent || attempt === maxAttempts) throw e;
      lastError = e;
      await sleep(backoffMs(attempt));
    }
  }

  throw lastError;
}

export async function putChunk(baseUrl, fileId, chunkIndex, body, headers, logger, opts = {}) {
  const maxAttempts = opts.maxAttempts ?? 4;
  const url = `${baseUrl}/electric/v1/file_chunk/${fileId}/${chunkIndex}`;
  let lastError;

  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      const t0 = performance.now();
      const resp = await fetch(url, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/octet-stream', ...headers },
        body
      });
      const elapsed = performance.now() - t0;
      const respBody = await resp.json().catch(() => ({ error: 'unparseable' }));

      if (logger) logger('PUT', url, null, respBody, resp.status);

      if (resp.ok) return { ...respBody, _timing: { put_ms: elapsed, attempts: attempt } };

      const err = new Error(`PUT chunk failed (${resp.status}): ${JSON.stringify(respBody)}`);
      if (resp.status < 500 && resp.status !== 408 && resp.status !== 429) {
        err.permanent = true;
        throw err;
      }
      lastError = err;
      if (attempt === maxAttempts) throw err;
      await sleep(backoffMs(attempt));
    } catch (e) {
      if (e.permanent || attempt === maxAttempts) throw e;
      lastError = e;
      await sleep(backoffMs(attempt));
    }
  }
  throw lastError;
}

export async function fetchShape(baseUrl, table, filterFn) {
  const rowMap = new Map();
  let offset = '-1';
  let handle = null;

  while (true) {
    const url = new URL(`${baseUrl}/electric/v1/${table}`);
    url.searchParams.set('offset', offset);
    if (handle) url.searchParams.set('handle', handle);

    const resp = await fetch(url, { cache: 'no-store' });
    if (!resp.ok) throw new Error(`Shape fetch failed: ${resp.status}`);

    if (!handle) handle = resp.headers.get('electric-handle');
    offset = resp.headers.get('electric-offset') || offset;

    const body = await resp.json();
    if (Array.isArray(body)) {
      applyShapeLog(rowMap, body);
    }

    const isUpToDate = resp.headers.has('electric-up-to-date')
      || body.some(e => e.headers?.control === 'up-to-date');
    if (isUpToDate) break;
  }

  const rows = [...rowMap.values()];
  return filterFn ? rows.filter(filterFn) : rows;
}

export async function fetchShapeWhere(baseUrl, table, where) {
  const rowMap = new Map();
  let offset = '-1';
  let handle = null;

  while (true) {
    const url = new URL(`${baseUrl}/electric/v1/shapes`);
    url.searchParams.set('table', table);
    url.searchParams.set('where', where);
    url.searchParams.set('offset', offset);
    if (handle) url.searchParams.set('handle', handle);

    const resp = await fetch(url, { cache: 'no-store' });
    if (!resp.ok) throw new Error(`Shape fetch failed: ${resp.status}`);

    if (!handle) handle = resp.headers.get('electric-handle');
    offset = resp.headers.get('electric-offset') || offset;

    const body = await resp.json();
    if (Array.isArray(body)) {
      applyShapeLog(rowMap, body);
    }

    const isUpToDate = resp.headers.has('electric-up-to-date')
      || body.some(e => e.headers?.control === 'up-to-date');
    if (isUpToDate) break;
  }

  return [...rowMap.values()];
}
