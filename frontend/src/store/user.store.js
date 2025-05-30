import { defineStore } from 'pinia';
import * as $enigma from '../libs/enigma';
import { Wallet } from 'ethers';
import { web3Store } from './web3.store';
import { ref, watch, reactive, computed } from 'vue';
import { clearLockKeyCache } from '@lo-fi/local-data-lock';
import $swal from '../libs/swal';
import * as Y from 'yjs';
//import { WebrtcProvider } from 'y-webrtc';
import { IndexeddbPersistence } from '../libs/y-indexeddb';
import { WebrtcProvider } from '../libs/y-webrtc';
import { WebsocketProvider } from '../libs/y-websocket';
import crypto from 'crypto-browserify';

export const userStore = defineStore('user', () => {
	let encryptionManager = null; // Store injected instance
	const setEncryptionManager = (manager) => {
		encryptionManager = manager;
	};

	const defaultAvatar = '/img/profile.webp';
	const accountInfoKeys = ['name', 'notes', 'avatar'];
	const contactKeys = ['publicKey', 'address', 'name', 'notes', 'avatar', 'hidden', 'metaPublicKey'];
	const backupKeys = ['tag', 'shares'];

	const account = ref();
	const accountInfo = reactive({});

	const contactsMap = reactive({});
	const contacts = computed(() => Object.values(contactsMap));

	const rooms = reactive([]);
	const registeredMetaWallet = ref();

	const vaults = ref([]);
	const isOnline = ref(navigator.onLine);

	const logout = async () => {
		await encryptionManager.disconnect();
		closeStorage();
		clearLockKeyCache();
		account.value = null;
		for (const key in accountInfo) {
			delete accountInfo[key];
		}
		for (const key in contactsMap) {
			delete contactsMap[key];
		}
		contacts.length = 0;
		registeredMetaWallet.value = null;
	};

	const checkMetaWallet = async () => {
		try {
			if (account.value && !registeredMetaWallet.value) {
				const metaPublicKey = await web3Store().registryContract.metaPublicKeys(account.value.address);
				if (metaPublicKey && metaPublicKey.length > 2) {
					registeredMetaWallet.value = true;
				}
			}
		} catch (error) {
			console.error('checkMetaWallet error', error);
		}
	};

	const yJs = {};

	const closeStorage = () => {
		if (yJs.accountObserver) yJs.account.unobserve(yJs.accountObserver);
		if (yJs.contactsObserver) yJs.contacts.unobserve(yJs.contactsObserver);
		if (yJs.accountInfoWatcher) yJs.accountInfoWatcher();
		if (yJs.contactsWatcher) yJs.contactsWatcher();
		if (yJs.rtc) yJs.rtc.destroy();
		if (yJs.server) yJs.server.destroy();
		if (yJs.persistence) yJs.persistence.destroy();
		if (yJs.doc) yJs.doc.destroy();
		for (const key in yJs) {
			yJs[key] = null;
		}
	};

	const openStorage = async (options) => {
		closeStorage();

		yJs.doc = new Y.Doc();

		yJs.persistence = new IndexeddbPersistence(`buckitup-${account.value.address}`, yJs.doc, { encrypt, decrypt });
		yJs.persistence.whenSynced.then(() => {
			console.log(`Local storage loaded `, options);

			yJs.account = yJs.doc.getMap('account');
			const accInf = yJs.account.get('accountInfo');

			if (accInf && (accInf.name || accInf.notes || accInf.avatar)) {
				Object.assign(accountInfo, accInf);
			} else {
				Object.assign(accountInfo, options?.accountInfo ? options.accountInfo : {});
			}

			yJs.accountObserver = (event) => {
				console.log('accountObserver', event);
				let changed = false;
				const data = yJs.account.get('accountInfo') || {};
				if (JSON.stringify(data) !== JSON.stringify(accountInfo)) {
					Object.assign(accountInfo, data);
					changed = true;
				}
				if (changed) {
					console.log('accountInfo updated from Y.Map', data);
				}
			};
			yJs.account.observe(yJs.accountObserver);

			yJs.accountInfoWatcher = watch(accountInfo, () => {
				console.log('accountInfoWatcher', accountInfo);
				yJs.account.set('accountInfo', { ...accountInfo });
				encryptionManager.setData(toVaultFormat());
				encryptionManager.updateAccountInfoVault(accountInfo);
			});

			yJs.contacts = yJs.doc.getMap('contacts');
			const initial = yJs.contacts.toJSON();
			for (const key in initial) {
				contactsMap[key] = initial[key];
			}

			yJs.contactsObserver = () => {
				const all = yJs.contacts.toJSON();
				let changed = false;

				for (const key in all) {
					if (JSON.stringify(contactsMap[key]) !== JSON.stringify(all[key])) {
						contactsMap[key] = all[key];
						changed = true;
					}
				}
				// Remove deleted keys
				Object.keys(contactsMap).forEach((k) => {
					if (!all[k]) {
						delete contactsMap[k];
						changed = true;
					}
				});

				if (changed) {
					console.log('contacts updated from Y.Map', all);
				}
			};

			yJs.contacts.observe(yJs.contactsObserver);

			yJs.contactsWatcher = watch(
				contactsMap,
				(newVal, oldVal) => {
					const newKeys = new Set(Object.keys(newVal));
					// Set or update
					for (const [publicKey, contact] of Object.entries(newVal)) {
						yJs.contacts.set(publicKey, contact);
					}
					// Delete keys that were removed
					if (oldVal) {
						for (const key of Object.keys(oldVal)) {
							if (!newKeys.has(key)) {
								yJs.contacts.delete(key);
							}
						}
					}
					encryptionManager.setData(toVaultFormat());
				},
				{ deep: true },
			);

			yJs.rtc = new WebrtcProvider(account.value.address, yJs.doc, {
				signaling: [
					//'ws://localhost:3951',
					//'wss://signaling.yjs.dev',
					'wss://buckitupss.appdev.pp.ua/signaling',
				],
				auth,
			});
			yJs.rtc.on('synced', () => {
				console.log(`WebRTC peers synced`);
				const accInf = yJs.account.get('accountInfo');
				Object.assign(accountInfo, accInf);
				yJs.contacts = yJs.doc.getMap('contacts');
				const cont = yJs.contacts.toJSON();
				Object.assign(contactsMap, cont);
				if (options?.callback) {
					options.callback();
					options.callback = null;
				}
			});
			yJs.rtc.on('peer-conn', async ({ peer, webrtcConn }) => {
				const handshakeOk = await setupSharedSecretAuth(peer); // твоя логіка перевірки
				if (!handshakeOk) {
					console.warn('🚫 Peer failed handshake');
					peer.destroy();
					return;
				}
				console.log('✅ Peer verified');
				webrtcConn._startSync(); // запускаємо sync вручну
			});

			yJs.server = new WebsocketProvider('wss://buckitupss.appdev.pp.ua/server', account.value.address, yJs.doc, { privateKey: account.value.privateKey });
		});

		// Sync clients with the y-websocket provider

		async function auth() {
			const ts = Math.floor(Date.now() / 1000);
			const room = account.value.address;
			const message = `${room}:${ts}`;
			const wallet = new Wallet(account.value.privateKey);
			const sig = await wallet.signMessage(message);
			return { sig, ts, room };
		}

		function encrypt(data) {
			if (data.length > 10) {
				const keyBuffer = crypto.createHash('sha256').update(account.value.privateKey).digest();
				const cipher = crypto.createCipheriv('aes-256-ctr', keyBuffer, Buffer.alloc(16, 0));
				const encrypted = Buffer.concat([cipher.update(data), cipher.final()]);
				return new Uint8Array(encrypted);
			} else {
				return data;
			}
		}

		function decrypt(data) {
			if (data.length > 10) {
				const keyBuffer = crypto.createHash('sha256').update(account.value.privateKey).digest();
				const decipher = crypto.createDecipheriv('aes-256-ctr', keyBuffer, Buffer.alloc(16, 0));
				const decrypted = Buffer.concat([decipher.update(Buffer.from(data)), decipher.final()]);
				return new Uint8Array(decrypted);
			} else {
				return data;
			}
		}
	};

	async function setupSharedSecretAuth(peer) {
		return new Promise((resolve) => {
			const myChallenge = $enigma.generateSecurePassword(32);
			const mySignature = $enigma.signChallenge(new TextEncoder().encode(myChallenge), account.value.privateKeyB64);

			peer.on('data', (raw) => {
				try {
					const data = JSON.parse(raw.toString());
					if (data.type === 'shared-auth-init') {
						const publicKeyB64 = $enigma.recoverPublicKey(data.challenge, data.signature);

						resolve(publicKeyB64 === account.value.publicKeyB64); // ✅ check
					}
				} catch (e) {
					resolve(false);
				}
			});

			peer.send(
				JSON.stringify({
					type: 'shared-auth-init',
					challenge: myChallenge,
					signature: mySignature,
				}),
			);
		});
	}

	const toVaultFormat = () => {
		const v = [
			[accountInfo.name, $enigma.combineKeypair(account.value.privateKeyB64, account.value.publicKeyB64)],
			[...rooms],
			Object.fromEntries(Object.entries(contactsMap).map(([publicKey, contact]) => [publicKey, { name: contact.name, notes: contact.notes, avatar: contact.avatar }])),
			{}, // add payload to differ 3rd generation
		];
		//console.log(v);
		return JSON.stringify(v);
	};

	const fromVaultFormat = async (vault) => {
		let privateKey;

		if (typeof vault === 'string') vault = JSON.parse(vault);
		if (vault?.length) {
			const spl = $enigma.splitKeypair(vault[0][1]);
			privateKey = '0x' + $enigma.convertPrivateKeyToHex(spl.privateKey);

			Object.assign(rooms, vault[1]);
		} else {
			privateKey = vault.privateKey;
		}

		account.value = await generateAccount(privateKey);
	};

	const generateAccount = async (pk) => {
		try {
			let privateKeyHex, publicKeyHex, privateKeyB64, publicKeyB64;
			if (!pk) {
				const keys = $enigma.generateKeypair();
				privateKeyHex = '0x' + $enigma.convertPrivateKeyToHex(keys.privateKey);
				publicKeyHex = '0x' + $enigma.convertPrivateKeyToHex(keys.publicKey);
				privateKeyB64 = keys.privateKey;
				publicKeyB64 = keys.publicKey;
			} else {
				const prks = pk.slice(2);
				const pbks = $enigma.getPublicKeyFromPrivateKey(prks);
				privateKeyHex = pk;
				publicKeyHex = '0x' + $enigma.convertPrivateKeyToHex(pbks);
				privateKeyB64 = $enigma.stringToBase64($enigma.hexToUint8Array(prks));
				publicKeyB64 = $enigma.stringToBase64(pbks);
			}

			const wallet = new Wallet(privateKeyHex);
			const signature = await wallet.signMessage(privateKeyHex);
			const meta = await web3Store().bukitupClient.generateKeysFromSignature(signature);
			const combinedKeyPairB64 = $enigma.combineKeypair(privateKeyB64, publicKeyB64);

			const account = {
				wallet,
				address: wallet.address,
				privateKey: privateKeyHex,
				privateKeyB64,
				publicKey: publicKeyHex,
				publicKeyB64,
				metaPublicKey: meta.spendingKeyPair.account.publicKey,
				metaPrivateKey: meta.spendingKeyPair.privatekey,
				combinedKeyPairB64,
			};

			return account;
		} catch (error) {
			console.error('generateAccount error', error);
		}
	};

	async function clearIndexedDB() {
		return new Promise((resolve, reject) => {
			let databases = indexedDB.databases();
			databases.then((dbs) => {
				let deletions = dbs.map((db) => indexedDB.deleteDatabase(db.name));
				Promise.all(deletions).then(resolve).catch(reject);
			});
		});
	}

	function checkOnline() {
		if (!isOnline.value) {
			$swal.fire({
				icon: 'error',
				title: 'No connection to Internet',
				footer: 'Connect to Internet to continue',
				timer: 15000,
			});
			return false;
		}
		return true;
	}

	return {
		vaults,
		logout,

		account,
		accountInfo,
		contacts,
		contactsMap,
		rooms,

		defaultAvatar,

		toVaultFormat,
		fromVaultFormat,
		generateAccount,

		setEncryptionManager,
		clearIndexedDB,

		accountInfoKeys,
		contactKeys,
		backupKeys,

		checkMetaWallet,
		registeredMetaWallet,
		checkOnline,
		isOnline,

		openStorage,
	};
});
