import * as secp from '@noble/secp256k1';
import blf from './blowfish';
import jsSHA from 'jssha/dist/sha3';
import { sha256, encodeBase64, decodeBase64 } from 'ethers';
import { hmac } from '@noble/hashes/hmac';
import { sha256 as sha256N } from '@noble/hashes/sha256';
secp.etc.hmacSha256Sync = (k, ...m) => hmac(sha256N, k, secp.etc.concatBytes(...m));

/**
 * Creates an ECDSA secp256k1 signature for the SHA-256 hash of the input data.
 *
 * - The input `dataB64` is expected in base64 format.
 * - It is hashed internally using SHA-256.
 * - A compact 64-byte signature (R||S) is produced and returned in base64 format.
 *
 * @param {string} dataB64 - Raw data (in base64) to be hashed using SHA-256.
 * @param {string} privateKeyB64 - 32-byte private key in base64 format.
 * @returns {Promise<string>} - Compact signature (64 bytes, R||S) in base64 format.
 */
export const signDigest = async (dataB64, privateKeyB64) => {
	const hashedDataB64 = base64ToSha256(dataB64);
	const digest = base64ToArray(hashedDataB64);
	const privKey = base64ToArray(privateKeyB64);
	const signatureObj = await secp.signAsync(digest, privKey, { lowS: true, extraEntropy: false });
	const compactRaw = signatureObj.toCompactRawBytes();
	return arrayToBase64(compactRaw);
};

/**
 * Signs a simple string challenge using secp256k1 and returns a base64-encoded signature.
 *
 * Steps:
 * 1. Hash the challenge string using SHA-256.
 * 2. Decode the private key from base64 to a Uint8Array.
 * 3. Generate the compact signature (r || s) and recovery ID.
 * 4. Combine r, s, and recovery ID into a single Uint8Array.
 * 5. Encode the combined signature into a base64 string for output.
 *
 * @param {string} challenge - The plain text challenge to be signed.
 * @param {string} privateKeyB64 - The private key in base64 format.
 * @returns {string} - Base64-encoded compact signature (r || s || recovery).
 */
export const signChallenge = (challenge, privateKeyB64) => {
	const digest = sha256(challenge).toString();
	const privKey = base64ToArray(privateKeyB64);

	// Generate the signature with recovery ID
	const { r, s, recovery } = secp.sign(digest, privKey, { lowS: true, extraEntropy: false });
	const rBytes = bigintToBytes(r); // 32 bytes
	const sBytes = bigintToBytes(s); // 32 bytes
	// Combine r, s, and recovery (1 byte) into a single Uint8Array
	const combined = new Uint8Array(65); // r (32) + s (32) + recovery (1)
	combined.set(rBytes, 0); // Set r at index 0
	combined.set(sBytes, 32); // Set s at index 32
	combined[64] = recovery; // Set recovery at index 64

	return arrayToBase64(combined);
};
/**
 * Recovers the public key from a signed challenge and its combined signature.
 *
 * Steps:
 * 1. Hash the challenge string using SHA-256.
 * 2. Decode the combined base64 signature into its components.
 * 3. Extract the compact signature (`r || s`) and recovery ID.
 * 4. Create a Signature object from the compact signature and recovery ID.
 * 5. Use the Signature object to recover the public key from the hash.
 * 6. Return the public key in base64 format (compressed format).
 *
 * @param {string} challenge - The plain text challenge that was signed.
 * @param {string} signatureCombinedB64 - Base64-encoded compact signature (r || s || recovery).
 * @returns {string} - Base64-encoded recovered public key in compressed format.
 */
export const recoverPublicKey = (challenge, signatureCombinedB64) => {
	// Hash the input challenge using SHA-256
	const digest = base64ToArray(base64ToSha256(Buffer.from(challenge).toString('base64')));
	// Decode the combined base64 signature
	const combined = base64ToArray(signatureCombinedB64);
	// Extract the signature and recovery ID
	const compactSig = combined.slice(0, -1); // All but the last byte
	const recoveryId = combined[combined.length - 1]; // The last byte
	// Create a Signature object from the compact signature
	const signature = secp.Signature.fromCompact(compactSig).addRecoveryBit(recoveryId);
	// Use the Signature object to recover the public key
	const publicKey = signature.recoverPublicKey(digest);

	return arrayToBase64(publicKey.toRawBytes(true));
};
export const bigintToBytes = (value, byteLength = 32) => {
	const hex = value.toString(16).padStart(byteLength * 2, '0'); // Convert to hex, padded to 32 bytes
	return Uint8Array.from(Buffer.from(hex, 'hex')); // Convert hex to Uint8Array
};
/**
 * Verifies a 64-byte compact signature (R||S) for the SHA-256 hash of the given input data.
 *
 * - The input data is hashed using SHA-256.
 * - The signature and public key are provided in base64 format.
 *
 * @param {string} signatureB64 - Compact signature (64 bytes, base64).
 * @param {string} dataB64 - Original data in base64, to be hashed internally using SHA-256.
 * @param {string} publicKeyB64 - Public key in base64 format (33 or 65 bytes).
 * @returns {boolean} - true if the signature is valid, otherwise false.
 */
export const isValidSignDigest = (signatureB64, dataB64, publicKeyB64) => {
	const signatureBytes = base64ToArray(signatureB64);
	const signatureObj = secp.Signature.fromCompact(signatureBytes);
	const hashedDataB64 = base64ToSha256(dataB64);
	const digest = base64ToArray(hashedDataB64);
	const pubKey = base64ToArray(publicKeyB64);
	return secp.verify(signatureObj, digest, pubKey);
};
export const compactPubpikKeyToAddress = (publickKeyB64) => {
	const pkh = convertPublicKeyToHex(publickKeyB64);
	// Convert compact public key to a Buffer
	const pubKeyBuffer = Buffer.from(compactPubKey, 'hex');
	// Hash the public key using keccak256
	const hash = keccak256(pubKeyBuffer);
	// Ethereum address is the last 20 bytes of the hash
	const address = '0x' + hash.slice(-20).toString('hex');
	return address;
};

export const publicKeyToAddress = (publickKey) => {
	if (!publickKey) return null;
	// Convert compact public key to a Buffer
	const pubKeyBuffer = Buffer.from(publickKey, 'hex');
	// Hash the public key using keccak256
	const hash = keccak256(pubKeyBuffer);
	// Ethereum address is the last 20 bytes of the hash
	const address = '0x' + hash.slice(-20).toString('hex');
	return address;
};

/**
 * Encrypts data using Blowfish in CFB mode.
 * @param {string} base64PlainData - Plain data in base64 format.
 * @param {string} base64Password - Password in base64 format.
 * @returns {string} - Encrypted data in base64 format.
 */
export const encryptData = (base64PlainData, base64Password) => {
	const { pass, iv } = deriveKeyAndIV(base64Password);
	const ciphered = blowfishCFB(Buffer.from(base64PlainData, 'base64'), pass, iv, false);
	return ciphered.toString('base64');
};
/**
 * Decrypts data using Blowfish in CFB mode.
 * @param {string} base64CipheredData - Encrypted data in base64 format.
 * @param {string} base64Password - Password in base64 format.
 * @returns {string} - Decrypted data in base64 format.
 */
export const decryptData = (base64CipheredData, base64Password) => {
	const { pass, iv } = deriveKeyAndIV(base64Password);
	const deciphered = blowfishCFB(Buffer.from(base64CipheredData, 'base64'), pass, iv, true);
	return deciphered.toString('base64');
};

/**
 * Generates a keypair for ECDH.
 * @returns {Object} - Object containing the public and private keys in base64 format.
 */
export const generateKeypair = () => {
	const privateKey = secp.utils.randomPrivateKey();
	const publicKey = getPublicKeyFromPrivateKey(privateKey, true);
	return {
		publicKey: arrayToBase64(publicKey),
		privateKey: arrayToBase64(privateKey),
	};
};
export const getPublicKeyFromPrivateKey = (privateKey, compressed = true) => {
	return secp.getPublicKey(privateKey, compressed);
};

export const generateSecurePassword = (len) => {
	const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
	return Array.from(crypto.getRandomValues(new Uint8Array(len)))
		.map((n) => chars[n % chars.length])
		.join('');
};

/**
 * Computes a shared secret using ECDH.
 * @param {string} base64PrivateKey - Private key in base64 format.
 * @param {string} base64PublicKey - Public key in base64 format.
 * @returns {string} - Shared secret in base64 format.
 */
export const computeSharedSecret = (base64PrivateKey, base64PublicKey) => {
	const privateKeyArray = base64ToArray(base64PrivateKey);
	const publicKeyArray = base64ToArray(base64PublicKey);
	const sharedSecret = secp.getSharedSecret(privateKeyArray, publicKeyArray, true);
	return arrayToBase64(sharedSecret);
};
/**
 * Encrypts data using a shared secret.
 * @param {string} base64PlainData - Plain data in base64 format.
 * @param {string} base64PrivateKey - Private key in base64 format.
 * @param {string} base64PublicKey - Public key in base64 format.
 * @returns {string} - Encrypted data in base64 format.
 */
export const encryptWithSharedSecret = (base64PlainData, base64PrivateKey, base64PublicKey) => {
	const sharedSecret = computeSharedSecret(base64PrivateKey, base64PublicKey);
	return encryptData(base64PlainData, sharedSecret);
};
/**
 * Creates a shortcode from a full key.
 * @param {string} base64FullKey - Full key in base64 format.
 * @returns {string} - Shortcode in hexadecimal format.
 */
export const shortcodeFromFullKey = (base64FullKey) => {
	const buffer = Buffer.from(base64FullKey, 'base64');
	const publicKey = Buffer.from(new Uint8Array(buffer.buffer, 32, 33)).toString('base64');
	const publicHash = hash(publicKey);
	const hashBuffer = Buffer.from(publicHash, 'base64');
	const code = Buffer.from(new Uint8Array(hashBuffer.buffer, 0, 3));
	return code.toString('hex');
};
/**
 * Combines private and public keys into a single Base64-encoded string.
 * @param {string} privateKeyB64 - Private key in base64 format.
 * @param {string} publicKeyB64 - Public key in base64 format.
 * @returns {string} - Combined key in base64 format.
 */
export const combineKeypair = (privateKeyB64, publicKeyB64) => {
	const combined = new Uint8Array(32 + 33);
	const privateKeyArray = base64ToArray(privateKeyB64);
	const publicKeyArray = base64ToArray(publicKeyB64);
	combined.set(privateKeyArray, 0);
	combined.set(publicKeyArray, 32);
	return arrayToBase64(combined);
};
/**
 * Splits a combined key (Base64) back into private and public keys.
 * @param {string} combinedKeyBase64 - Combined key in base64 format.
 * @returns {Object} - Object containing `privateKey` and `publicKey` in base64 format.
 */
export const splitKeypair = (combinedKeyBase64) => {
	const combinedArray = base64ToArray(combinedKeyBase64);
	const privateKeyArray = combinedArray.slice(0, 32);
	const publicKeyArray = combinedArray.slice(32);
	const privateKeyBase64 = arrayToBase64(privateKeyArray);
	const publicKeyBase64 = arrayToBase64(publicKeyArray);
	return {
		privateKey: privateKeyBase64,
		publicKey: publicKeyBase64,
	};
};
// Private methods and properties
/**
 * Derives a key and initialization vector (IV) from a password.
 * @param {string} base64Password - Password in base64 format.
 * @returns {Object} - Object containing the key and initialization vector.
 */
export const deriveKeyAndIV = (base64Password) => {
	const passBuffer = Buffer.from(base64Password, 'base64');
	const pass = passBuffer.slice(8, 24); // 16 bytes for the key
	const key1 = passBuffer.slice(0, 8); // First 8 bytes
	const key2 = passBuffer.slice(24, 32); // Last 8 bytes
	const iv = Buffer.alloc(8);
	for (let i = 0; i < 8; i++) {
		iv[i] = key1[i] ^ key2[i]; // Generate IV using XOR
	}
	return { pass, iv };
};
/**
 * Implements Blowfish encryption/decryption in CFB mode.
 * @param {Buffer} data - Data to process.
 * @param {Buffer} key - Key for Blowfish.
 * @param {Buffer} iv - Initialization vector.
 * @param {boolean} decrypt - Flag indicating decryption.
 * @returns {Buffer} - Processed data.
 */
export const blowfishCFB = (data, key, iv, decrypt = false) => {
	const context = blf.key(key);
	return blf.cfb(context, iv, data, decrypt);
};
// Utility methods for data conversion
/**
 * Hashes data using SHA3-256.
 * @param {string} base64Data - Data in base64 format.
 * @returns {string} - Hashed data in base64 format.
 */
export const hash = (base64Data) => {
	const shaObj = new jsSHA('SHA3-256', 'B64');
	shaObj.update(base64Data);
	return shaObj.getHash('B64');
};

export const hexToUint8Array = (hex) => {
	if (hex.startsWith('0x')) hex = hex.slice(2); // Remove 0x prefix if present
	return Uint8Array.from(Buffer.from(hex, 'hex'));
};

/**
 * Hashes data using SHA3-256.
 * @param {string} base64Data - Data in base64 format.
 * @returns {string} - Hashed data in base64 format.
 */
export const base64Tohash = (base64Data) => {
	const shaObj = new jsSHA('SHA3-256', 'B64');
	shaObj.update(base64Data);
	return shaObj.getHash('B64');
};
/**
 * Hashes data encoded in base64 format using SHA-256
 * and returns the result in base64 format.
 *
 * @param {string} base64Data - Data in base64 format.
 * @returns {string} - SHA-256 hash of the data in base64 format (32 bytes).
 */
export const base64ToSha256 = (base64Data) => {
	// Decode base64 data to bytes
	const dataBytes = decodeBase64(base64Data);
	// Compute SHA-256 hash
	const hashBytes = sha256(dataBytes);
	// Ethers' sha256 returns a hex string; convert it to bytes first, then base64
	const hashBase64 = encodeBase64(hashBytes);
	return hashBase64;
};
/**
 * Converts base64 data to a string.
 * @param {string} base64Data - Data in base64 format.
 * @returns {string} - Decoded string.
 */
export const base64ToString = (base64Data) => {
	return Buffer.from(base64Data, 'base64').toString('utf-8');
};
/**
 * Converts base64 data to a Uint8Array.
 * @param {string} base64Data - Data in base64 format.
 * @returns {Uint8Array} - Byte array.
 */
export const base64ToArray = (base64Data) => {
	const buffer = Buffer.from(base64Data, 'base64');
	return new Uint8Array(buffer.buffer, buffer.byteOffset, buffer.byteLength);
};
/**
 * Converts a Uint8Array to a base64 string.
 * @param {Uint8Array} array - Byte array.
 * @returns {string} - Data in base64 format.
 */
export const arrayToBase64 = (array) => {
	return Buffer.from(array).toString('base64');
};
/**
 * Converts a string to a base64 string.
 * @param {string} string - Original string.
 * @returns {string} - Data in base64 format.
 */
export const stringToBase64 = (string) => {
	return Buffer.from(string, 'utf-8').toString('base64');
};
/**
 * Converts a public key from base64 to hexadecimal format.
 * @param {string} publicKeyBase64 - Public key in base64 format.
 * @returns {string} - Public key in hexadecimal format.
 */
export const convertPublicKeyToHex = (publicKeyBase64) => {
	const publicKeyArray = base64ToArray(publicKeyBase64);
	return Buffer.from(publicKeyArray).toString('hex');
};
/**
 * Converts a private key from base64 to hexadecimal format.
 * @param {string} privateKeyBase64 - Private key in base64 format.
 * @returns {string} - Private key in hexadecimal format.
 */
export const convertPrivateKeyToHex = (privateKeyBase64) => {
	const privateKeyArray = base64ToArray(privateKeyBase64);
	return Buffer.from(privateKeyArray).toString('hex');
};

export const encryptDataSync = (data, privateKey) => {
	const base64PlainData = stringToBase64(JSON.stringify({ data, type: typeof data })); // Store type info
	const { pass, iv } = deriveKeyAndIV(stringToBase64(privateKey));
	const ciphered = blowfishCFB(Buffer.from(base64PlainData, 'base64'), pass, iv, false);
	return ciphered.toString('base64');
};

export const decryptDataSync = (encryptedData, privateKey) => {
	const { pass, iv } = deriveKeyAndIV(stringToBase64(privateKey));
	const deciphered = blowfishCFB(Buffer.from(encryptedData, 'base64'), pass, iv, true);
	const decoded = JSON.parse(deciphered.toString());
	return decoded.type === 'number' ? Number(decoded.data) : decoded.data; // Restore original type
};

export const decryptObjectKeys = (encryptedObject, keys, privateKey) => {
	const decryptedObject = {};
	Object.assign(decryptedObject, encryptedObject);

	for (const key of keys) {
		if (key in encryptedObject) {
			const decrypted = decryptDataSync(encryptedObject[key], privateKey);
			decryptedObject[key] = decrypted;
		}
	}
	return decryptedObject;
};
export const encryptObjectKeys = (decryptedObject, keys, privateKey) => {
	const encryptedObject = {}; // Clone object to avoid mutations

	for (const key of keys) {
		if (key in decryptedObject) {
			const encrypted = encryptDataSync(decryptedObject[key], privateKey);
			encryptedObject[key] = encrypted;
		}
	}

	return encryptedObject;
};
