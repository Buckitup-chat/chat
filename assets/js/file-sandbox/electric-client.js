import { signMlDsa87, uint8ToBase64Unpadded, base64ToUint8 } from './crypto.js';

const textEncoder = new TextEncoder();

export async function getChallenge(baseUrl) {
  const resp = await fetch(`${baseUrl}/electric/v1/challenge`, {
    headers: { 'Accept': 'application/json' }
  });
  if (!resp.ok) throw new Error(`Challenge request failed: ${resp.status}`);
  return resp.json();
}

export async function ingest(baseUrl, mutations, signSkey, logger) {
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

  if (!resp.ok) throw new Error(`Ingest failed (${resp.status}): ${JSON.stringify(body)}`);
  return body;
}

export async function fetchShape(baseUrl, table, filterFn) {
  const rows = [];
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
      for (const entry of body) {
        if (entry.value) rows.push(entry.value);
      }
    }

    const isUpToDate = resp.headers.has('electric-up-to-date')
      || body.some(e => e.headers?.control === 'up-to-date');
    if (isUpToDate) break;
  }

  return filterFn ? rows.filter(filterFn) : rows;
}

export async function fetchShapeWhere(baseUrl, table, where) {
  const rows = [];
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
      for (const entry of body) {
        if (entry.value) rows.push(entry.value);
      }
    }

    const isUpToDate = resp.headers.has('electric-up-to-date')
      || body.some(e => e.headers?.control === 'up-to-date');
    if (isUpToDate) break;
  }

  return rows;
}
