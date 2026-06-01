import { signMlDsa87, uint8ToBase64Unpadded, base64ToUint8 } from './crypto.js';

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

// Statuses worth retrying: backpressure (429/503 from the ingest throttle),
// expired challenge (401 — a fresh one is fetched on the next attempt), and
// transient server/proxy errors. 4xx like 400/403/409/422 are permanent.
function isRetryableStatus(status) {
  return status === 401 || status === 408 || status === 425 ||
    status === 429 || status === 500 || status === 502 ||
    status === 503 || status === 504;
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
 * Retry-After). Throws on permanent errors or once `maxAttempts` is exhausted —
 * so a transient failure no longer abandons the whole upload (which previously
 * left orphaned chunks and never-finalized files).
 */
export async function ingest(baseUrl, mutations, signSkey, logger, opts = {}) {
  const maxAttempts = opts.maxAttempts ?? 6;
  let lastError;

  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      const challengeResp = await getChallenge(baseUrl);
      if (logger) logger('GET', `${baseUrl}/electric/v1/challenge`, null, challengeResp, 200);

      const challengeBytes = textEncoder.encode(challengeResp.challenge);
      const signature = signMlDsa87(challengeBytes, signSkey);
      const signatureB64 = uint8ToBase64Unpadded(signature);

      const payload = {
        mutations,
        auth: {
          challenge_id: challengeResp.challenge_id,
          signature: signatureB64
        }
      };

      const resp = await fetch(`${baseUrl}/electric/v1/ingest`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Accept': 'application/json' },
        body: JSON.stringify(payload)
      });

      const body = await resp.json().catch(() => ({ error: 'unparseable response' }));
      if (logger) logger('POST', `${baseUrl}/electric/v1/ingest`, payload, body, resp.status);

      if (resp.ok) return body;

      const httpError = new Error(`Ingest failed (${resp.status}): ${JSON.stringify(body)}`);
      if (!isRetryableStatus(resp.status)) {
        httpError.permanent = true;
        throw httpError;
      }

      lastError = httpError;
      if (attempt === maxAttempts) throw httpError;
      await sleep(retryDelayMs(resp, attempt));
    } catch (e) {
      // Non-retryable HTTP errors give up immediately; network/fetch
      // rejections fall through to a backoff retry.
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
