import { defineStore } from 'pinia';
import * as $enigma from '../libs/enigma';
import { Wallet } from 'ethers';
import { web3Store } from './web3.store';
import { ref, watch, reactive, computed } from 'vue';
import { clearLockKeyCache } from '@lo-fi/local-data-lock';
import $swal from '../libs/swal';
import * as Y from 'yjs';
import { toRaw } from 'vue';
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
		try {
			if (yJs.accountObserver && yJs.account?.unobserve) {
				yJs.account.unobserve(yJs.accountObserver);
			}

			if (yJs.contactsObserver && yJs.contacts?.unobserve) {
				yJs.contacts.unobserve(yJs.contactsObserver);
			}

			if (typeof yJs.accountInfoWatcher === 'function') {
				yJs.accountInfoWatcher();
			}

			if (typeof yJs.contactsWatcher === 'function') {
				yJs.contactsWatcher();
			}

			if (yJs.rtc?.destroy) {
				yJs.rtc.destroy();
			}

			if (yJs.server?.destroy) {
				yJs.server.destroy();
			}

			if (yJs.persistence?.destroy) {
				yJs.persistence.destroy();
			}

			if (yJs.doc?.destroy) {
				yJs.doc.destroy();
			}
		} catch (err) {
			console.warn('Error during storage cleanup:', err);
		}

		// Clear all references in yJs
		for (const key in yJs) {
			yJs[key] = null;
		}
	};

	const openStorage = async (options) => {
		closeStorage();

		yJs.key = crypto.createHash('sha256').update(account.value.privateKey).digest();

		yJs.doc = new Y.Doc();

		yJs.persistence = new IndexeddbPersistence(`buckitup-${account.value.address}`, yJs.doc);
		yJs.persistence.whenSynced.then(() => {
			console.log(`Local storage loaded `, options);

			yJs.account = yJs.doc.getMap('account');
			const accInf = yJs.account.get('accountInfo');

			const hasEncryptedData = accInf && typeof accInf === 'object' && accountInfoKeys.some((key) => accInf[key]);

			if (hasEncryptedData) {
				Object.assign(accountInfo, decrypt(accInf, accountInfoKeys));
			} else {
				Object.assign(accountInfo, options?.accountInfo ?? {});
			}

			yJs.accountObserver = (event) => {
				console.log('accountObserver', event);
				const accInf = yJs.account.get('accountInfo');
				if (accInf) {
					const decrypted = decrypt(accInf, accountInfoKeys);

					if (decrypted && typeof decrypted === 'object' && accountInfoKeys.every((k) => k in decrypted)) {
						for (let key of accountInfoKeys) {
							if (decrypted[key] !== accountInfo[key]) {
								Object.assign(accountInfo, decrypted);
								console.log('accountObserver updated', decrypted);
								break;
							}
						}
					}
				}
			};
			yJs.account.observe(yJs.accountObserver);

			yJs.accountInfoWatcher = watch(accountInfo, () => {
				console.log('accountInfoWatcher', accountInfo);
				yJs.account.set('accountInfo', encrypt(toRaw(accountInfo), accountInfoKeys));
				encryptionManager.setData(toVaultFormat());
				encryptionManager.updateAccountInfoVault(accountInfo);
			});

			yJs.contacts = yJs.doc.getMap('contacts');
			const initial = yJs.contacts.toJSON();
			for (const key in initial) {
				contactsMap[key] = decrypt(initial[key], contactKeys);
			}

			yJs.contactsObserver = () => {
				syncContactsFromYjs();
			};

			yJs.contacts.observe(yJs.contactsObserver);

			yJs.contactsWatcher = watch(
				contactsMap,
				(newVal, oldVal) => {
					const newKeys = new Set(Object.keys(newVal));
					// Set or update
					for (const [publicKey, contact] of Object.entries(newVal)) {
						yJs.contacts.set(publicKey, encrypt(contact, contactKeys));
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
				signChallenge,
			});
			yJs.rtc.on('synced', () => {
				console.log(`WebRTC peers synced`);

				const accInf = yJs.account.get('accountInfo');
				if (accInf) {
					console.log(`synced`, accInf);
					const decrypted = decrypt(accInf, accountInfoKeys);

					for (let key of accountInfoKeys) {
						if (decrypted[key] !== accountInfo[key]) {
							Object.assign(accountInfo, decrypted);
							console.log('accountInfo updated from Y.Map', decrypted);
							break;
						}
					}
				}
				syncContactsFromYjs();

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

		function syncContactsFromYjs() {
			const all = yJs.contacts.toJSON();
			if (all && typeof all === 'object') {
				for (const key in all) {
					const decrypted = decrypt(all[key], contactKeys);
					for (const cKey of contactKeys) {
						if (!contactsMap[key] || contactsMap[key][cKey] !== decrypted[cKey]) {
							contactsMap[key] = decrypted;
							console.log('contact updated');
							break;
						}
					}
				}
				Object.keys(contactsMap).forEach((k) => {
					if (!all[k]) {
						delete contactsMap[k];
						console.log('contact deleted');
					}
				});
			}
		}

		// Sync clients with the y-websocket provider

		async function auth() {
			const ts = Math.floor(Date.now() / 1000);
			const room = account.value.address;
			const message = `${room}:${ts}`;
			const wallet = new Wallet(account.value.privateKey);
			const sig = await wallet.signMessage(message);
			return { sig, ts, room };
		}

		async function signChallenge(challenge) {
			const wallet = new Wallet(account.value.privateKey);
			return await wallet.signMessage(challenge);
		}

		function encrypt(obj, keys) {
			const result = {};
			console.log('encrypt', obj, keys);
			for (const field of keys) {
				const value = obj[field] || null;
				const serialized = JSON.stringify(value);
				const cipher = crypto.createCipheriv('aes-256-ctr', yJs.key, Buffer.alloc(16, 0));
				const encrypted = Buffer.concat([cipher.update(Buffer.from(serialized, 'utf-8')), cipher.final()]);
				result[field] = encrypted.toString('base64');
			}

			return result;
		}

		function decrypt(obj, keys) {
			const result = {};
			console.log('decrypt', obj, keys);
			for (const field of keys) {
				const base64 = obj[field];
				if (typeof base64 !== 'string') continue;

				try {
					const decipher = crypto.createDecipheriv('aes-256-ctr', yJs.key, Buffer.alloc(16, 0));
					const decrypted = Buffer.concat([decipher.update(Buffer.from(base64, 'base64')), decipher.final()]);
					result[field] = JSON.parse(decrypted.toString('utf-8'));
				} catch (err) {
					console.error(`Failed to decrypt or parse field "${field}"`, err);
					result[field] = null;
				}
			}

			return result;
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
