import {
  base64ToUint8, uint8ToBase64Unpadded, uint8ToBase64Padded,
  uint8ToHex, hexToUint8,
  signMlDsa87, hash, encryptChunk, decryptChunk,
  buildSignaturePayload
} from './file-sandbox/crypto.js';
import { ingest, fetchShape, fetchShapeWhere } from './file-sandbox/electric-client.js';
import { chunkFile, generateFileId, generateEncSecret } from './file-sandbox/file-chunker.js';
import { VideoSWStreamer } from './file-sandbox/video-sw-streamer.js';
import {
  classifyFile, fileMime, extractImageMetadata, extractVideoMetadata,
  buildFileContent, buildImageContent, buildVideoContent,
  parseContentObject, thumbHashToDataURL
} from './file-sandbox/content-types.js';

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
  document.getElementById('play-video-btn').addEventListener('click', handlePlayVideo);
  document.getElementById('close-preview-btn').addEventListener('click', closePreview);
  document.getElementById('close-video-btn').addEventListener('click', closeVideo);
  document.getElementById('clear-log-btn').addEventListener('click', clearLog);
  document.getElementById('toggle-docs-btn').addEventListener('click', toggleDocs);
  document.getElementById('refresh-files-btn').addEventListener('click', loadMyFiles);
  document.getElementById('copy-content-json-btn').addEventListener('click', copyContentJson);
  document.getElementById('extract-btn').addEventListener('click', handleExtract);
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
      sign_skey: base64ToUint8(identity.sign_skey),
      ...(identity.crypt_pkey && { crypt_pkey: base64ToUint8(identity.crypt_pkey) }),
      ...(identity.crypt_skey && { crypt_skey: base64ToUint8(identity.crypt_skey) }),
      ...(identity.contact_pkey && { contact_pkey: base64ToUint8(identity.contact_pkey) }),
      ...(identity.contact_skey && { contact_skey: base64ToUint8(identity.contact_skey) }),
    };

    document.getElementById('key-status').textContent =
      `Loaded: ${identity.name} (${identity.user_hash.slice(0, 18)}...)`;
    document.getElementById('upload-section').classList.remove('hidden');
    document.getElementById('my-files-section').classList.remove('hidden');
    setStatus('Keys imported successfully', 'success');
    loadMyFiles();
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
    const encSecretB64 = uint8ToBase64Unpadded(encSecret);
    const contentJson = await buildContentJson(file, fileId, encSecretB64);
    addUploadedFile(fileId, file.name, file.size, encSecretHex, contentJson);
    showContentJson(contentJson);
    updateProgress(chunks.length, chunks.length, 'Complete');
    setStatus(`Uploaded ${file.name} — save the encryption secret!`, 'success');
    fileInput.value = '';
    loadMyFiles();
  } catch (e) {
    console.error('Upload failed:', e);
    setStatus(`Upload failed: ${e.message}`, 'error');
  } finally {
    uploadBtn.disabled = false;
  }
}

// --- Content JSON ---

async function buildContentJson(file, fileId, encSecretB64) {
  const mime = fileMime(file);
  const category = classifyFile(file);
  const ts = Math.floor((file.lastModified || Date.now()) / 1000);

  let contentObj;
  if (category === 'image') {
    const meta = await extractImageMetadata(file);
    contentObj = buildImageContent(
      meta.widthAspect, meta.heightAspect, meta.thumbHashB64,
      file.name, file.size, mime, ts, fileId, encSecretB64
    );
  } else if (category === 'video') {
    const meta = await extractVideoMetadata(file);
    contentObj = buildVideoContent(
      meta.widthAspect, meta.heightAspect, meta.thumbHashB64,
      file.name, file.size, mime, ts, fileId, encSecretB64
    );
  } else {
    contentObj = buildFileContent(file.name, file.size, mime, ts, fileId, encSecretB64);
  }

  return JSON.stringify(contentObj);
}

function showContentJson(json) {
  const textarea = document.getElementById('content-json-textarea');
  textarea.value = json;
  document.getElementById('content-json-output').classList.remove('hidden');
}

function copyContentJson() {
  const textarea = document.getElementById('content-json-textarea');
  navigator.clipboard.writeText(textarea.value).then(() => {
    const btn = document.getElementById('copy-content-json-btn');
    const prev = btn.textContent;
    btn.textContent = 'Copied!';
    setTimeout(() => { btn.textContent = prev; }, 1500);
  });
}

// --- Extract ---

function handleExtract() {
  const input = document.getElementById('extract-json-input').value.trim();
  if (!input) return setStatus('Paste content JSON first', 'error');

  const resultEl = document.getElementById('extract-result');
  const infoEl = document.getElementById('extract-info');
  const previewEl = document.getElementById('extract-preview');
  const actionsEl = document.getElementById('extract-actions');

  infoEl.innerHTML = '';
  previewEl.innerHTML = '';
  actionsEl.innerHTML = '';
  resultEl.classList.add('hidden');

  try {
    const desc = parseContentObject(input);

    if (desc.type === 'text') {
      infoEl.innerHTML = `<strong>Type:</strong> text<br><strong>Content:</strong> ${escapeHtml(desc.content)}`;
      resultEl.classList.remove('hidden');
      setStatus('Parsed text content', 'success');
      return;
    }

    if (desc.type === 'composed') {
      infoEl.innerHTML = `<strong>Type:</strong> composed message (${desc.elements.length} elements)`;
      resultEl.classList.remove('hidden');
      setStatus('Parsed composed message', 'success');
      return;
    }

    const isInline = desc.type === 'inline_file' || desc.type === 'inline_image';
    const hasThumbHash = desc.thumbHashB64 && desc.thumbHashB64.length > 0;

    let info = `<strong>Type:</strong> ${desc.type}`;
    if (desc.name) info += `<br><strong>Name:</strong> ${escapeHtml(desc.name)}`;
    if (desc.size != null) info += `<br><strong>Size:</strong> ${formatBytes(desc.size)}`;
    if (desc.mimeType) info += `<br><strong>MIME:</strong> ${desc.mimeType}`;
    if (desc.fileId) info += `<br><strong>File ID:</strong> <code>${desc.fileId}</code>`;
    if (desc.widthAspect != null) info += `<br><strong>Aspect:</strong> ${desc.widthAspect}:${desc.heightAspect}`;
    infoEl.innerHTML = info;

    if (hasThumbHash) {
      try {
        const dataUrl = thumbHashToDataURL(base64ToUint8(desc.thumbHashB64));
        previewEl.innerHTML = `<img src="${dataUrl}" style="max-width:200px;border-radius:0.375rem;border:1px solid #e5e7eb" alt="ThumbHash preview">`;
      } catch { /* skip preview on failure */ }
    }

    if (isInline) {
      const downloadBtn = document.createElement('button');
      downloadBtn.className = 'px-3 py-1 bg-green-600 text-white rounded hover:bg-green-700 text-sm';
      downloadBtn.textContent = 'Download';
      downloadBtn.addEventListener('click', () => downloadInlineContent(desc));
      actionsEl.appendChild(downloadBtn);

      if (desc.type === 'inline_image') {
        const viewBtn = document.createElement('button');
        viewBtn.className = 'px-3 py-1 bg-purple-600 text-white rounded hover:bg-purple-700 text-sm';
        viewBtn.textContent = 'Preview';
        viewBtn.addEventListener('click', () => previewInlineImage(desc));
        actionsEl.appendChild(viewBtn);
      }
    } else {
      const goBtn = document.createElement('button');
      goBtn.className = 'px-3 py-1 bg-green-600 text-white rounded hover:bg-green-700 text-sm';
      goBtn.textContent = 'Fill Download Form';
      goBtn.addEventListener('click', () => {
        const secretHex = uint8ToHex(base64ToUint8(desc.encSecretB64));
        document.getElementById('download-file-id').value = desc.fileId;
        document.getElementById('download-enc-secret').value = secretHex;
        document.getElementById('download-section').scrollIntoView({ behavior: 'smooth' });
      });
      actionsEl.appendChild(goBtn);
    }

    resultEl.classList.remove('hidden');
    setStatus(`Parsed ${desc.type} content`, 'success');
  } catch (e) {
    setStatus(`Parse failed: ${e.message}`, 'error');
  }
}

function downloadInlineContent(desc) {
  const bytes = base64ToUint8(desc.dataB64);
  const blob = new Blob([bytes], { type: desc.mimeType || 'application/octet-stream' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = desc.name || 'download';
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
}

function previewInlineImage(desc) {
  const bytes = base64ToUint8(desc.dataB64);
  const blob = new Blob([bytes], { type: desc.mimeType || 'image/png' });
  if (previewBlobUrl) URL.revokeObjectURL(previewBlobUrl);
  previewBlobUrl = URL.createObjectURL(blob);
  document.getElementById('preview-img').src = previewBlobUrl;
  document.getElementById('image-preview').classList.remove('hidden');
}

function escapeHtml(str) {
  const d = document.createElement('div');
  d.textContent = str;
  return d.innerHTML;
}

// --- Download ---

async function fetchManifest(fileId) {
  setStatus('Fetching file manifest...', 'info');
  const files = await fetchShapeWhere(state.baseUrl, 'files', `file_id = '${fileId}'`);
  if (files.length === 0) throw new Error('File manifest not found');
  return files[0];
}

async function fetchChunk(fileId, index) {
  const resp = await fetch(`${state.baseUrl}/electric/v1/file_chunk/${fileId}/${index}`);
  if (resp.status === 404) throw new Error(`Chunk ${index} not found`);
  if (!resp.ok) throw new Error(`Chunk fetch failed: ${resp.status}`);
  return new Uint8Array(await resp.arrayBuffer());
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
    const manifest = await fetchManifest(fileId);
    const chunkCount = parseInt(manifest.chunk_count);

    let fileHandle = null;
    if (window.showSaveFilePicker) {
      try {
        fileHandle = await window.showSaveFilePicker({
          suggestedName: `download_${fileId}`,
        });
      } catch (e) {
        if (e.name === 'AbortError') throw e;
        console.warn('File System Access API failed, falling back to blob download:', e);
      }
    } else {
      console.warn('File System Access API not supported, using blob download fallback');
    }

    if (fileHandle) {
      const writable = await fileHandle.createWritable();
      try {
        for (let i = 0; i < chunkCount; i++) {
          updateProgress(i, chunkCount, 'Downloading');
          const chunk = await fetchChunk(fileId, i);
          const decrypted = await decryptChunk(chunk, encSecret);
          await writable.write(decrypted);
        }
      } finally {
        await writable.close();
      }
    } else {
      const decryptedChunks = [];
      for (let i = 0; i < chunkCount; i++) {
        updateProgress(i, chunkCount, 'Downloading');
        const chunk = await fetchChunk(fileId, i);
        decryptedChunks.push(
          await decryptChunk(chunk, encSecret)
        );
      }
      const blob = new Blob(decryptedChunks);
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `download_${fileId}`;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      URL.revokeObjectURL(url);
    }

    updateProgress(chunkCount, chunkCount, 'Complete');
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
    const manifest = await fetchManifest(fileId);
    const chunkCount = parseInt(manifest.chunk_count);

    const decryptedChunks = [];
    for (let i = 0; i < chunkCount; i++) {
      updateProgress(i, chunkCount, 'Downloading');
      const chunk = await fetchChunk(fileId, i);
      decryptedChunks.push(
        await decryptChunk(chunk, encSecret)
      );
    }
    const blob = new Blob(decryptedChunks);

    if (previewBlobUrl) URL.revokeObjectURL(previewBlobUrl);
    previewBlobUrl = URL.createObjectURL(blob);

    const img = document.getElementById('preview-img');
    img.src = previewBlobUrl;
    document.getElementById('image-preview').classList.remove('hidden');

    updateProgress(chunkCount, chunkCount, 'Complete');
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

// --- Video Streaming ---

let activeStreamer = null;

async function handlePlayVideo() {
  const fileId = document.getElementById('download-file-id').value.trim();
  const encSecretHex = document.getElementById('download-enc-secret').value.trim();

  if (!fileId || !encSecretHex) return setStatus('Enter file_id and encryption secret', 'error');

  const playBtn = document.getElementById('play-video-btn');
  playBtn.disabled = true;
  setStatus('Starting video stream...', 'info');

  try {
    closeVideo();
    closePreview();

    const encSecret = hexToUint8(encSecretHex);
    const files = await fetchShape(state.baseUrl, 'file', r => r.file_id === fileId);
    if (files.length === 0) throw new Error('File manifest not found');

    const manifest = files[0];
    const chunkCount = parseInt(manifest.chunk_count);
    const totalSize = parseInt(manifest.total_size);

    const videoElement = document.getElementById('preview-video');
    const chunkSize = parseInt(manifest.chunk_size) || 4_194_304;
    activeStreamer = new VideoSWStreamer({
      fileId,
      encSecret,
      chunkCount,
      totalSize,
      chunkSize,
      videoElement,
      baseUrl: state.baseUrl,
      onStatus(msg, type) { setVideoStatus(msg); setStatus(msg, type); }
    });

    document.getElementById('video-player').classList.remove('hidden');
    await activeStreamer.start();
  } catch (e) {
    console.error('Video stream failed:', e);
    setStatus(`Video stream failed: ${e.message}`, 'error');
  } finally {
    playBtn.disabled = false;
  }
}

function closeVideo() {
  if (activeStreamer) {
    activeStreamer.destroy();
    activeStreamer = null;
  }
  document.getElementById('video-player').classList.add('hidden');
}

function setVideoStatus(msg) {
  document.getElementById('video-status').textContent = msg;
}

// --- My Files ---

async function loadMyFiles() {
  if (!state.keys) return;

  const listEl = document.getElementById('files-list');
  listEl.innerHTML = '<p class="text-sm text-gray-500 italic">Loading...</p>';

  try {
    const files = await fetchShapeWhere(
      state.baseUrl, 'files',
      `uploader_hash = '${state.keys.user_hash}'`
    );
    console.log('[My Files] fetched', files.length, 'files:', files);
    renderFilesList(files);
  } catch (e) {
    listEl.innerHTML = `<p class="text-sm status-error">Failed to load files: ${e.message}</p>`;
  }
}

function renderFilesList(files) {
  const listEl = document.getElementById('files-list');

  if (files.length === 0) {
    listEl.innerHTML = '<p class="text-sm text-gray-500 italic">No files uploaded yet</p>';
    return;
  }

  const rows = files.map(f => {
    const size = formatBytes(parseInt(f.total_size));
    const shortId = f.file_id;
    const deleted = f.deleted_flag === 'true' || f.deleted_flag === true || f.deleted_flag === 't';
    const rowClass = deleted ? 'border-b opacity-50' : 'border-b';
    const nameStyle = deleted ? 'line-through' : '';
    return `
      <tr class="${rowClass}">
        <td class="py-2 pr-3 font-mono text-xs" style="text-decoration:${nameStyle}">${shortId}</td>
        <td class="py-2 pr-3 text-sm">${size}</td>
        <td class="py-2 pr-3 text-sm">${f.chunk_count}</td>
        <td class="py-2 text-sm space-x-2">${deleted
          ? '<span class="px-2 py-1 bg-gray-200 text-gray-500 rounded text-xs">Deleted</span>'
          : `<button class="x-use-file px-2 py-1 bg-green-100 text-green-800 rounded text-xs hover:bg-green-200"
            data-file-id="${f.file_id}">Use</button>
          <button class="x-delete-file px-2 py-1 bg-red-100 text-red-800 rounded text-xs hover:bg-red-200"
            data-file-id="${f.file_id}">Delete</button>`}
        </td>
      </tr>`;
  }).join('');

  listEl.innerHTML = `
    <table class="w-full text-left">
      <thead>
        <tr class="border-b text-xs text-gray-500 uppercase">
          <th class="py-2 pr-3">File ID</th>
          <th class="py-2 pr-3">Size</th>
          <th class="py-2 pr-3">Chunks</th>
          <th class="py-2">Actions</th>
        </tr>
      </thead>
      <tbody>${rows}</tbody>
    </table>`;

  listEl.querySelectorAll('.x-use-file').forEach(btn => {
    btn.addEventListener('click', () => {
      document.getElementById('download-file-id').value = btn.dataset.fileId;
      document.getElementById('download-enc-secret').value = '';
      document.getElementById('download-enc-secret').focus();
    });
  });

  listEl.querySelectorAll('.x-delete-file').forEach(btn => {
    btn.addEventListener('click', () => handleDeleteFile(btn.dataset.fileId));
  });
}

async function handleDeleteFile(fileId) {
  if (!state.keys) return;
  if (!confirm(`Delete file ${fileId}?`)) return;

  setStatus('Deleting file...', 'info');

  try {
    const files = await fetchShapeWhere(state.baseUrl, 'files', `file_id = '${fileId}'`);
    if (files.length === 0) throw new Error('File not found');

    const manifest = files[0];
    const newTimestamp = parseInt(manifest.owner_timestamp) + 1;

    const signableFields = {
      chunk_count: parseInt(manifest.chunk_count),
      chunk_sign_hashes: [],
      chunk_size: parseInt(manifest.chunk_size),
      deleted_flag: true,
      file_id: fileId,
      owner_timestamp: newTimestamp,
      total_size: parseInt(manifest.total_size),
      uploader_hash: state.keys.user_hash
    };

    const payloadStr = buildSignaturePayload(signableFields);
    const payloadBytes = textEncoder.encode(payloadStr);
    const signB64 = signMlDsa87(payloadBytes, state.keys.sign_skey);

    const mutation = {
      type: 'update',
      original: { file_id: fileId, uploader_hash: state.keys.user_hash },
      changes: {
        deleted_flag: true,
        chunk_sign_hashes: [],
        owner_timestamp: newTimestamp,
        sign_b64: uint8ToBase64Unpadded(signB64)
      },
      syncMetadata: { relation: 'files' }
    };

    await ingest(state.baseUrl, [mutation], state.keys.sign_skey, addLogEntry);
    setStatus(`Deleted file ${fileId}`, 'success');
    loadMyFiles();
  } catch (e) {
    console.error('Delete failed:', e);
    setStatus(`Delete failed: ${e.message}`, 'error');
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

function addUploadedFile(fileId, fileName, size, encSecretHex, contentJson) {
  state.uploadedFiles.push({ fileId, fileName, size, encSecretHex, contentJson });
  renderUploadedFiles();
}

function renderUploadedFiles() {
  const list = document.getElementById('uploaded-files');
  list.innerHTML = state.uploadedFiles.map((f, i) => `
    <div class="uploaded-file">
      <div><strong>${f.fileName}</strong> (${formatBytes(f.size)})</div>
      <div class="file-id">file_id: <code>${f.fileId}</code></div>
      <div class="enc-secret">enc_secret: <code>${f.encSecretHex}</code></div>
      ${f.contentJson ? `
        <details class="mt-2">
          <summary class="text-xs text-gray-600 cursor-pointer">Content JSON</summary>
          <pre class="mt-1 text-xs bg-gray-100 p-2 rounded overflow-x-auto whitespace-pre-wrap break-all">${escapeHtml(f.contentJson)}</pre>
          <button class="x-copy-content-json mt-1 px-2 py-0.5 bg-gray-200 text-gray-700 rounded text-xs hover:bg-gray-300" data-index="${i}">Copy</button>
        </details>
      ` : ''}
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

  list.querySelectorAll('.x-copy-content-json').forEach(btn => {
    btn.addEventListener('click', () => {
      const f = state.uploadedFiles[parseInt(btn.dataset.index)];
      navigator.clipboard.writeText(f.contentJson).then(() => {
        const prev = btn.textContent;
        btn.textContent = 'Copied!';
        setTimeout(() => { btn.textContent = prev; }, 1500);
      });
    });
  });
}

function formatBytes(bytes) {
  if (bytes >= 1024 * 1024) return `${(bytes / 1024 / 1024).toFixed(2)} MB`;
  if (bytes >= 1024) return `${(bytes / 1024).toFixed(2)} KB`;
  return `${bytes} bytes`;
}
