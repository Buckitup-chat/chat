const DEFAULT_CHUNK_SIZE = 4_194_304; // 4 MB

export function chunkFile(arrayBuffer, chunkSize = DEFAULT_CHUNK_SIZE) {
  const chunks = [];
  for (let offset = 0; offset < arrayBuffer.byteLength; offset += chunkSize) {
    const len = Math.min(chunkSize, arrayBuffer.byteLength - offset);
    chunks.push(new Uint8Array(arrayBuffer, offset, len));
  }
  return chunks;
}

export function generateFileId() {
  return 'f_' + uuidv7().replace(/-/g, '');
}

export function generateEncSecret() {
  return crypto.getRandomValues(new Uint8Array(32));
}

function uuidv7() {
  const now = Date.now();
  const timeHex = now.toString(16).padStart(12, '0');
  const rand = crypto.getRandomValues(new Uint8Array(10));

  // Set version (7) in bits 48-51
  rand[0] = (rand[0] & 0x0f) | 0x70;
  // Set variant (10xx) in bits 64-65
  rand[2] = (rand[2] & 0x3f) | 0x80;

  const randHex = Array.from(rand, b => b.toString(16).padStart(2, '0')).join('');
  const hex = timeHex + randHex;

  return [
    hex.slice(0, 8),
    hex.slice(8, 12),
    hex.slice(12, 16),
    hex.slice(16, 20),
    hex.slice(20, 32)
  ].join('-');
}
