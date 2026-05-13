import { ml_dsa87 } from '@noble/post-quantum/ml-dsa';
import { sha3_512 } from '@noble/hashes/sha3';

// --- Base64 helpers ---

export function uint8ToBase64Padded(bytes) {
  let binary = '';
  for (let i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes[i]);
  return btoa(binary);
}

export function uint8ToBase64Unpadded(bytes) {
  return uint8ToBase64Padded(bytes).replace(/=+$/, '');
}

export function base64ToUint8(b64) {
  const padded = b64 + '='.repeat((4 - (b64.length % 4)) % 4);
  const binary = atob(padded);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

export function hexToUint8(hex) {
  if (hex.startsWith('\\x')) hex = hex.slice(2);
  if (hex.startsWith('0x')) hex = hex.slice(2);
  const bytes = new Uint8Array(hex.length / 2);
  for (let i = 0; i < bytes.length; i++) bytes[i] = parseInt(hex.substr(i * 2, 2), 16);
  return bytes;
}

export function uint8ToHex(bytes) {
  return Array.from(bytes, b => b.toString(16).padStart(2, '0')).join('');
}

// --- ML-DSA-87 ---

export function signMlDsa87(messageBytes, secretKey) {
  return ml_dsa87.sign(secretKey, messageBytes);
}

export function verifyMlDsa87(signature, messageBytes, publicKey) {
  return ml_dsa87.verify(publicKey, messageBytes, signature);
}

// --- SHA3-512 (matches EnigmaPq.hash/1) ---

export function hash(data) {
  return sha3_512(data);
}

// --- AES-256-GCM ---

export async function encryptChunk(plaintext, encSecret) {
  const nonce = crypto.getRandomValues(new Uint8Array(12));
  const key = await crypto.subtle.importKey('raw', encSecret, 'AES-GCM', false, ['encrypt']);
  const ciphertext = await crypto.subtle.encrypt(
    { name: 'AES-GCM', iv: nonce, tagLength: 128 },
    key,
    plaintext
  );
  const result = new Uint8Array(12 + ciphertext.byteLength);
  result.set(nonce, 0);
  result.set(new Uint8Array(ciphertext), 12);
  return result;
}

export async function decryptChunk(blob, encSecret) {
  const nonce = blob.slice(0, 12);
  const ciphertextWithTag = blob.slice(12);
  const key = await crypto.subtle.importKey('raw', encSecret, 'AES-GCM', false, ['decrypt']);
  const plaintext = await crypto.subtle.decrypt(
    { name: 'AES-GCM', iv: nonce, tagLength: 128 },
    key,
    ciphertextWithTag
  );
  return new Uint8Array(plaintext);
}

// --- Integrity signature payload ---
// Replicates Chat.Data.Integrity.signature_payload/1 exactly.
// Fields are sorted alphabetically by key name, each encoded per suffix rules,
// then concatenated into a single string that gets signed.

export function buildSignaturePayload(fields) {
  const sorted = Object.entries(fields).sort(([a], [b]) => a.localeCompare(b));
  return sorted.map(([key, value]) => encodeField(key, value)).join('');
}

function encodeField(key, value) {
  if (key.endsWith('_b64') || key.endsWith('_cert') || key.endsWith('_pkey')) {
    if (value === null || value === undefined) return 'null';
    return uint8ToBase64Padded(value);
  }
  if (Array.isArray(value)) {
    return value.map(el => {
      if (el instanceof Uint8Array) return uint8ToBase64Padded(el);
      return String(el);
    }).join('');
  }
  if (value === true) return 'true';
  if (value === false) return 'false';
  if (value === null || value === undefined) return 'null';
  if (typeof value === 'number') return String(value);
  if (typeof value === 'string') return value;
  return String(value);
}
