import * as Y from 'yjs';
import { WebrtcProvider } from 'y-webrtc';
import { IndexeddbPersistence } from '../libs/y-indexeddb';
import crypto from 'crypto-browserify'; // ✅ use this instead of node:crypto for browser!

const SECRET_KEY = 'super_secret_key'; // your custom encryption key

export const ydoc = new Y.Doc();
const roomName = 'buckitup'; // shared room

const provider = new WebrtcProvider(roomName, ydoc, {
	signaling: ['ws://localhost:4444'],
	//password: SECRET_KEY, // optional encryption of signaling phase (not document encryption)
});

provider.on('synced', () => {
	console.log('WebRTC peers synced!');
});

// --- Setup encrypted IndexedDB persistence ---
const persistence = new IndexeddbPersistence('buckitup', ydoc, {
	encode: (update) => encrypt(update, SECRET_KEY),
	decode: (update) => decrypt(update, SECRET_KEY),
});

persistence.whenSynced.then(() => {
	console.log('Local encrypted storage loaded!');
});

// --- ENCRYPTION HELPERS ---

function encrypt(data, key) {
	if (data.length > 10) {
		console.log('encrypt1', data, key);
		const keyBuffer = crypto.createHash('sha256').update(key).digest();
		const cipher = crypto.createCipheriv('aes-256-ctr', keyBuffer, Buffer.alloc(16, 0));
		const encrypted = Buffer.concat([cipher.update(data), cipher.final()]);
		console.log('encrypt2', encrypted);
		return new Uint8Array(encrypted);
	} else {
		return data;
	}
}

function decrypt(data, key) {
	console.log('decrypted', data, key);
	if (data.length > 10) {
		const keyBuffer = crypto.createHash('sha256').update(key).digest();
		const decipher = crypto.createDecipheriv('aes-256-ctr', keyBuffer, Buffer.alloc(16, 0));
		const decrypted = Buffer.concat([decipher.update(Buffer.from(data)), decipher.final()]);

		return new Uint8Array(decrypted);
	} else {
		return data;
	}
}
