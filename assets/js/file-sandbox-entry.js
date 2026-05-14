import {
  base64ToUint8, uint8ToBase64Unpadded, uint8ToBase64Padded,
  uint8ToHex, hexToUint8,
  signMlDsa87, hash, encryptChunk, decryptChunk,
  buildSignaturePayload
} from './file-sandbox/crypto.js';
import { ingest, fetchShape } from './file-sandbox/electric-client.js';
import { chunkFile, generateFileId, generateEncSecret } from './file-sandbox/file-chunker.js';

const CHUNK_SIZE = 4_194_304;
const textEncoder = new TextEncoder();

let state = {
  keys: null,
  baseUrl: window.location.origin,
  uploadedFiles: []
};

// --- UI Initialization ---

function init() {
  document.getElementById('import-btn').addEventListener('click', handleKeyImport);
  document.getElementById('upload-btn').addEventListener('click', handleUpload);
  document.getElementById('download-btn').addEventListener('click', handleDownload);
  document.getElementById('view-btn').addEventListener('click', handleView);
  document.getElementById('close-preview-btn').addEventListener('click', closePreview);
  document.getElementById('clear-log-btn').addEventListener('click', clearLog);
  document.getElementById('toggle-docs-btn').addEventListener('click', toggleDocs);
}

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', init);
} else {
  init();
}

// --- Key Import ---

async function handleKeyImport() {
  const file = document.getElementById('key-file').files[0];
  if (!file) return setStatus('Select a key file first', 'error');

  try {
    const text = await file.text();
    const identity = JSON.parse(text);

    if (identity.type !== 'buckitup_pq_identity') {
      setStatus('Invalid key file: wrong type', 'error');
      return;
    }

    state.keys = {
      user_hash: identity.user_hash,
      name: identity.name,
      sign_pkey: base64ToUint8(identity.sign_pkey),
      sign_skey: base64ToUint8(identity.sign_skey)
    };

    document.getElementById('key-status').textContent =
      `Loaded: ${identity.name} (${identity.user_hash.slice(0, 18)}...)`;
    document.getElementById('upload-section').classList.remove('hidden');
    setStatus('Keys imported successfully', 'success');
  } catch (e) {
    setStatus(`Key import failed: ${e.message}`, 'error');
  }
}

// --- Upload ---

async function handleUpload() {
  if (!state.keys) return setStatus('Import keys first', 'error');

  const fileInput = document.getElementById('upload-file');
  const file = fileInput.files[0];
  if (!file) return setStatus('Select a file first', 'error');

  const uploadBtn = document.getElementById('upload-btn');
  uploadBtn.disabled = true;
  setStatus(`Uploading ${file.name} (${formatBytes(file.size)})...`, 'info');

  try {
    const arrayBuffer = await file.arrayBuffer();
    const chunks = chunkFile(arrayBuffer, CHUNK_SIZE);
    const fileId = generateFileId();
    const encSecret = generateEncSecret();
    const userHash = state.keys.user_hash;
    let baseTimestamp = Math.floor(Date.now() / 1000);

    const chunkSignatures = [];

    for (let i = 0; i < chunks.length; i++) {
      updateProgress(i, chunks.length, 'Encrypting & uploading');

      const encrypted = await encryptChunk(chunks[i], encSecret);
      const ownerTimestamp = baseTimestamp + i;

      const signableFields = {
        chunk_index: i,
        data_b64: encrypted,
        file_id: fileId,
        owner_timestamp: ownerTimestamp,
        size: encrypted.length,
        uploader_hash: userHash
      };

      const payloadStr = buildSignaturePayload(signableFields);
      const payloadBytes = textEncoder.encode(payloadStr);
      const signB64 = signMlDsa87(payloadBytes, state.keys.sign_skey);

      const mutation = {
        type: 'insert',
        modified: {
          file_id: fileId,
          chunk_index: i,
          data_b64: uint8ToBase64Unpadded(encrypted),
          size: encrypted.length,
          uploader_hash: userHash,
          owner_timestamp: ownerTimestamp,
          sign_b64: uint8ToBase64Unpadded(signB64)
        },
        syncMetadata: { relation: 'file_chunks' }
      };

      await ingest(state.baseUrl, [mutation], state.keys.sign_skey, addLogEntry);
      chunkSignatures.push(signB64);
    }

    // Build files manifest
    updateProgress(chunks.length, chunks.length, 'Uploading manifest');
    const chunkSignHashes = chunkSignatures.map(sig => hash(sig));
    const manifestTimestamp = baseTimestamp + chunks.length;

    const manifestFields = {
      chunk_count: chunks.length,
      chunk_sign_hashes: chunkSignHashes,
      chunk_size: CHUNK_SIZE,
      deleted_flag: false,
      file_id: fileId,
      owner_timestamp: manifestTimestamp,
      total_size: arrayBuffer.byteLength,
      uploader_hash: userHash
    };

    const manifestPayloadStr = buildSignaturePayload(manifestFields);
    const manifestPayloadBytes = textEncoder.encode(manifestPayloadStr);
    const manifestSignB64 = signMlDsa87(manifestPayloadBytes, state.keys.sign_skey);

    const manifestMutation = {
      type: 'insert',
      modified: {
        file_id: fileId,
        uploader_hash: userHash,
        total_size: arrayBuffer.byteLength,
        chunk_size: CHUNK_SIZE,
        chunk_count: chunks.length,
        chunk_sign_hashes: chunkSignHashes.map(h => uint8ToBase64Unpadded(h)),
        owner_timestamp: manifestTimestamp,
        deleted_flag: false,
        sign_b64: uint8ToBase64Unpadded(manifestSignB64)
      },
      syncMetadata: { relation: 'files' }
    };

    await ingest(state.baseUrl, [manifestMutation], state.keys.sign_skey, addLogEntry);

    const encSecretHex = uint8ToHex(encSecret);
    addUploadedFile(fileId, file.name, file.size, encSecretHex);
    updateProgress(chunks.length, chunks.length, 'Complete');
    setStatus(`Uploaded ${file.name} — save the encryption secret!`, 'success');
    fileInput.value = '';
  } catch (e) {
    console.error('Upload failed:', e);
    setStatus(`Upload failed: ${e.message}`, 'error');
  } finally {
    uploadBtn.disabled = false;
  }
}

// --- Download ---

function parseChunkData(rawData) {
  if (typeof rawData === 'string' && rawData.startsWith('\\x')) return hexToUint8(rawData);
  if (typeof rawData === 'string') return base64ToUint8(rawData);
  return new Uint8Array(rawData);
}

async function fetchAndSortChunks(fileId) {
  setStatus('Fetching file manifest...', 'info');
  const files = await fetchShape(state.baseUrl, 'file', r => r.file_id === fileId);
  if (files.length === 0) throw new Error('File manifest not found');

  const chunkCount = parseInt(files[0].chunk_count);
  setStatus(`Fetching ${chunkCount} chunk(s)...`, 'info');
  const chunkRows = await fetchShape(state.baseUrl, 'file_chunk', r => r.file_id === fileId);
  if (chunkRows.length < chunkCount) {
    throw new Error(`Missing chunks: have ${chunkRows.length}, need ${chunkCount}`);
  }

  chunkRows.sort((a, b) => parseInt(a.chunk_index) - parseInt(b.chunk_index));
  return chunkRows;
}

async function downloadStreaming(chunkRows, encSecret, fileHandle) {
  const writable = await fileHandle.createWritable();
  try {
    for (let i = 0; i < chunkRows.length; i++) {
      updateProgress(i, chunkRows.length, 'Decrypting');
      const decrypted = await decryptChunk(parseChunkData(chunkRows[i].data_b64), encSecret);
      await writable.write(decrypted);
    }
  } finally {
    await writable.close();
  }
}

async function decryptToBlob(chunkRows, encSecret) {
  const decryptedChunks = [];
  for (let i = 0; i < chunkRows.length; i++) {
    updateProgress(i, chunkRows.length, 'Decrypting');
    decryptedChunks.push(
      await decryptChunk(parseChunkData(chunkRows[i].data_b64), encSecret)
    );
  }
  return new Blob(decryptedChunks);
}

async function downloadInMemory(chunkRows, encSecret, fileId) {
  const blob = await decryptToBlob(chunkRows, encSecret);
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = `download_${fileId}`;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
}

async function handleDownload() {
  const fileId = document.getElementById('download-file-id').value.trim();
  const encSecretHex = document.getElementById('download-enc-secret').value.trim();

  if (!fileId || !encSecretHex) return setStatus('Enter file_id and encryption secret', 'error');

  const downloadBtn = document.getElementById('download-btn');
  downloadBtn.disabled = true;
  setStatus('Downloading...', 'info');

  try {
    const encSecret = hexToUint8(encSecretHex);

    let fileHandle = null;
    if (window.showSaveFilePicker) {
      fileHandle = await window.showSaveFilePicker({
        suggestedName: `download_${fileId}`,
      });
    }

    const chunkRows = await fetchAndSortChunks(fileId);

    if (fileHandle) {
      await downloadStreaming(chunkRows, encSecret, fileHandle);
    } else {
      await downloadInMemory(chunkRows, encSecret, fileId);
    }

    updateProgress(chunkRows.length, chunkRows.length, 'Complete');
    setStatus('Download complete', 'success');
  } catch (e) {
    if (e.name === 'AbortError') {
      setStatus('Download cancelled', 'info');
    } else {
      console.error('Download failed:', e);
      setStatus(`Download failed: ${e.message}`, 'error');
    }
  } finally {
    downloadBtn.disabled = false;
  }
}

let previewBlobUrl = null;

async function handleView() {
  const fileId = document.getElementById('download-file-id').value.trim();
  const encSecretHex = document.getElementById('download-enc-secret').value.trim();

  if (!fileId || !encSecretHex) return setStatus('Enter file_id and encryption secret', 'error');

  const viewBtn = document.getElementById('view-btn');
  viewBtn.disabled = true;
  setStatus('Decrypting for preview...', 'info');

  try {
    const encSecret = hexToUint8(encSecretHex);
    const chunkRows = await fetchAndSortChunks(fileId);
    const blob = await decryptToBlob(chunkRows, encSecret);

    if (previewBlobUrl) URL.revokeObjectURL(previewBlobUrl);
    previewBlobUrl = URL.createObjectURL(blob);

    const img = document.getElementById('preview-img');
    img.src = previewBlobUrl;
    document.getElementById('image-preview').classList.remove('hidden');

    updateProgress(chunkRows.length, chunkRows.length, 'Complete');
    setStatus('Preview ready', 'success');
  } catch (e) {
    console.error('View failed:', e);
    setStatus(`View failed: ${e.message}`, 'error');
  } finally {
    viewBtn.disabled = false;
  }
}

function closePreview() {
  document.getElementById('image-preview').classList.add('hidden');
  if (previewBlobUrl) {
    URL.revokeObjectURL(previewBlobUrl);
    previewBlobUrl = null;
  }
}

// --- UI Helpers ---

function setStatus(message, type) {
  const el = document.getElementById('status');
  el.textContent = message;
  el.className = `status-${type}`;
}

function updateProgress(current, total, label) {
  const pct = total > 0 ? Math.round((current / total) * 100) : 0;
  const bar = document.getElementById('progress-bar');
  const text = document.getElementById('progress-text');
  if (bar) bar.style.width = `${pct}%`;
  if (text) text.textContent = `${label}: ${current}/${total} chunks (${pct}%)`;
}

function addLogEntry(method, url, requestBody, responseBody, status) {
  const log = document.getElementById('request-log');
  const entry = document.createElement('div');
  entry.className = 'log-entry';

  const statusClass = status >= 200 && status < 300 ? 'status-ok' : 'status-err';
  const path = new URL(url, window.location.origin).pathname;

  entry.innerHTML = `
    <div class="log-header">
      <span class="log-method">${method} ${path}</span>
      <span class="log-status ${statusClass}">${status}</span>
    </div>
    <details class="log-details">
      <summary>Request Body</summary>
      <pre>${requestBody ? truncateJson(requestBody) : '(empty)'}</pre>
    </details>
    <details class="log-details">
      <summary>Response Body</summary>
      <pre>${JSON.stringify(responseBody, null, 2)}</pre>
    </details>
    <div class="log-time">${new Date().toLocaleTimeString()}</div>
  `;

  log.prepend(entry);
}

function truncateJson(obj) {
  const str = JSON.stringify(obj, (key, value) => {
    if (typeof value === 'string' && value.length > 200) {
      return value.slice(0, 100) + `... (${value.length} chars)`;
    }
    return value;
  }, 2);
  return str;
}

function clearLog() {
  document.getElementById('request-log').innerHTML = '';
}

function toggleDocs() {
  const docs = document.getElementById('docs-panel');
  docs.classList.toggle('hidden');
}

function addUploadedFile(fileId, fileName, size, encSecretHex) {
  state.uploadedFiles.push({ fileId, fileName, size, encSecretHex });
  renderUploadedFiles();
}

function renderUploadedFiles() {
  const list = document.getElementById('uploaded-files');
  list.innerHTML = state.uploadedFiles.map((f, i) => `
    <div class="uploaded-file">
      <div><strong>${f.fileName}</strong> (${formatBytes(f.size)})</div>
      <div class="file-id">file_id: <code>${f.fileId}</code></div>
      <div class="enc-secret">enc_secret: <code>${f.encSecretHex}</code></div>
      <button class="x-download-uploaded" data-index="${i}"
        style="margin-top:0.5rem;padding:0.25rem 0.75rem;background:#16a34a;color:white;border:none;border-radius:0.25rem;cursor:pointer;font-size:0.875rem">
        Download this file
      </button>
    </div>
  `).join('');

  list.querySelectorAll('.x-download-uploaded').forEach(btn => {
    btn.addEventListener('click', () => {
      const f = state.uploadedFiles[parseInt(btn.dataset.index)];
      document.getElementById('download-file-id').value = f.fileId;
      document.getElementById('download-enc-secret').value = f.encSecretHex;
      handleDownload();
    });
  });
}

function formatBytes(bytes) {
  if (bytes >= 1024 * 1024) return `${(bytes / 1024 / 1024).toFixed(2)} MB`;
  if (bytes >= 1024) return `${(bytes / 1024).toFixed(2)} KB`;
  return `${bytes} bytes`;
}
