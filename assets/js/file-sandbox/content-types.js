import { rgbaToThumbHash, thumbHashToDataURL } from 'thumbhash';

const MIME_BY_EXT = {
  jpg: 'image/jpeg', jpeg: 'image/jpeg', png: 'image/png', gif: 'image/gif',
  webp: 'image/webp', svg: 'image/svg+xml', bmp: 'image/bmp',
  mp4: 'video/mp4', webm: 'video/webm', mov: 'video/quicktime',
  avi: 'video/x-msvideo', mkv: 'video/x-matroska',
  pdf: 'application/pdf', zip: 'application/zip',
};

function gcd(a, b) {
  while (b) { [a, b] = [b, a % b]; }
  return a;
}

function reducedAspect(w, h) {
  if (!w || !h) return [1, 1];
  const d = gcd(w, h);
  return [w / d, h / d];
}

export function classifyFile(file) {
  const mime = fileMime(file);
  if (mime.startsWith('image/')) return 'image';
  if (mime.startsWith('video/')) return 'video';
  return 'file';
}

export function fileMime(file) {
  if (file.type) return file.type;
  const ext = file.name.split('.').pop()?.toLowerCase();
  return (ext && MIME_BY_EXT[ext]) || 'application/octet-stream';
}

export async function extractImageMetadata(file) {
  const url = URL.createObjectURL(file);
  try {
    const img = new Image();
    img.src = url;
    await new Promise((resolve, reject) => {
      img.onload = resolve;
      img.onerror = () => reject(new Error('Failed to load image'));
    });
    const [widthAspect, heightAspect] = reducedAspect(img.naturalWidth, img.naturalHeight);
    const thumbHashB64 = canvasThumbHash(img, img.naturalWidth, img.naturalHeight);
    return { widthAspect, heightAspect, thumbHashB64 };
  } finally {
    URL.revokeObjectURL(url);
  }
}

export async function extractVideoMetadata(file) {
  const url = URL.createObjectURL(file);
  try {
    const video = document.createElement('video');
    video.muted = true;
    video.preload = 'auto';
    video.src = url;

    await withTimeout(new Promise((resolve, reject) => {
      video.onloadeddata = resolve;
      video.onerror = () => reject(new Error('Failed to load video'));
    }), 5000);

    const [widthAspect, heightAspect] = reducedAspect(video.videoWidth, video.videoHeight);

    let thumbHashB64 = '';
    try {
      const seekTarget = Math.min(1, video.duration || 0);
      video.currentTime = seekTarget;
      await withTimeout(new Promise(r => { video.onseeked = r; }), 3000);
      thumbHashB64 = canvasThumbHash(video, video.videoWidth, video.videoHeight);
    } catch { /* thumbhash is best-effort */ }

    return { widthAspect, heightAspect, thumbHashB64 };
  } catch {
    return { widthAspect: 16, heightAspect: 9, thumbHashB64: '' };
  } finally {
    URL.revokeObjectURL(url);
  }
}

function canvasThumbHash(source, srcWidth, srcHeight) {
  const maxDim = 100;
  const scale = Math.min(maxDim / srcWidth, maxDim / srcHeight, 1);
  const w = Math.round(srcWidth * scale);
  const h = Math.round(srcHeight * scale);

  const canvas = document.createElement('canvas');
  canvas.width = w;
  canvas.height = h;
  const ctx = canvas.getContext('2d');
  ctx.drawImage(source, 0, 0, w, h);
  const { data } = ctx.getImageData(0, 0, w, h);

  const hash = rgbaToThumbHash(w, h, data);
  return uint8ToBase64(hash);
}

function uint8ToBase64(bytes) {
  let binary = '';
  for (let i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes[i]);
  return btoa(binary);
}

function base64ToUint8(b64) {
  const binary = atob(b64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

function withTimeout(promise, ms) {
  return Promise.race([
    promise,
    new Promise((_, reject) => setTimeout(() => reject(new Error('Timeout')), ms))
  ]);
}

// --- Content object builders ---

export function buildFileContent(name, size, mimeType, creationUnixtime, fileId, encSecretB64) {
  return { file: [name, size, mimeType, creationUnixtime, fileId, encSecretB64] };
}

export function buildImageContent(wAspect, hAspect, thumbHashB64, name, size, mimeType, creationUnixtime, fileId, encSecretB64) {
  return { image: [wAspect, hAspect, thumbHashB64, name, size, mimeType, creationUnixtime, fileId, encSecretB64] };
}

export function buildVideoContent(wAspect, hAspect, thumbHashB64, name, size, mimeType, creationUnixtime, fileId, encSecretB64) {
  return { video: [wAspect, hAspect, thumbHashB64, name, size, mimeType, creationUnixtime, fileId, encSecretB64] };
}

// --- Content object parser ---

const PARSERS = {
  file([name, size, mimeType, creationUnixtime, fileId, encSecretB64]) {
    return { type: 'file', name, size, mimeType, creationUnixtime, fileId, encSecretB64 };
  },
  image([wAspect, hAspect, thumbHashB64, name, size, mimeType, creationUnixtime, fileId, encSecretB64]) {
    return { type: 'image', widthAspect: wAspect, heightAspect: hAspect, thumbHashB64, name, size, mimeType, creationUnixtime, fileId, encSecretB64 };
  },
  video([wAspect, hAspect, thumbHashB64, name, size, mimeType, creationUnixtime, fileId, encSecretB64]) {
    return { type: 'video', widthAspect: wAspect, heightAspect: hAspect, thumbHashB64, name, size, mimeType, creationUnixtime, fileId, encSecretB64 };
  },
  inline_file([name, size, mimeType, creationUnixtime, dataB64]) {
    return { type: 'inline_file', name, size, mimeType, creationUnixtime, dataB64 };
  },
  inline_image([wAspect, hAspect, thumbHashB64, name, size, mimeType, creationUnixtime, dataB64]) {
    return { type: 'inline_image', widthAspect: wAspect, heightAspect: hAspect, thumbHashB64, name, size, mimeType, creationUnixtime, dataB64 };
  },
};

export function parseContentObject(jsonString) {
  const parsed = JSON.parse(jsonString);

  if (typeof parsed === 'string') return { type: 'text', content: parsed };

  if (Array.isArray(parsed)) return { type: 'composed', elements: parsed };

  if (typeof parsed === 'object' && parsed !== null) {
    const keys = Object.keys(parsed);
    if (keys.length === 1 && PARSERS[keys[0]]) {
      return PARSERS[keys[0]](parsed[keys[0]]);
    }
  }

  throw new Error(`Unrecognized content format: ${jsonString.slice(0, 80)}`);
}

export { thumbHashToDataURL, base64ToUint8 };
