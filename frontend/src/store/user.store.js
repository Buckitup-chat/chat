import { defineStore } from 'pinia';
import * as $enigma from '../libs/Enigma';
import { utils, Wallet } from 'ethers';
import { web3Store } from './web3.store';
//import piniaPluginPersistedstate from 'pinia-plugin-persistedstate';
import dayjs from 'dayjs';
import { ref, watch, onMounted, onUnmounted, shallowRef, inject, nextTick, reactive } from 'vue';
import { Client, Config } from '@dxos/client';
import { Defaults } from '@dxos/config';
import { Expando, create } from '@dxos/client/echo';
import { SpaceMember } from '@dxos/protocols/proto/dxos/halo/credentials';
import { clearLockKeyCache } from '@lo-fi/local-data-lock';

export const userStore = defineStore(
	'user',
	() => {
		const dxClient = shallowRef(
			new Client({
				config: new Config(Defaults()),
			}),
		);

		let encryptionManager = null; // Store injected instance
		const setEncryptionManager = (manager) => {
			encryptionManager = manager;
		};

		const account = ref();
		const defaultAvatar = '/img/profile.webp';

		const accountInfoKeys = ['name', 'notes', 'avatar'];
		const contactKeys = ['publicKey', 'address', 'name', 'notes', 'avatar', 'hidden', 'metaPublicKey'];
		const backupKeys = ['tag', 'shares'];

		const accountInfo = reactive({});
		let accountInfoDx;
		const space = shallowRef();
		const contacts = reactive([]);
		const contactsDx = reactive([]);
		const transactions = ref([]);

		const backups = reactive([]);
		const backupsDx = reactive([]);

		const vaults = ref([]);

		const vaults2 = ref([
			{
				address: '0x748d9c35b6bFD0AD3E05d891Ad97855c314C49ED',
				privateKey: '0xd292bd04cecd27f8ff12dad85b71b1d62a6da29863a94341ac618a5049494f9f',
				name: 'Roman Chvankov',
				notes: 'BuckitUp working profile',
				avatar: 'bafybeiaygoakof2slx3spdoy2nf6bqdghurqvfucka2mslh7b54bhhfim4',
			},
			{
				address: '0xAc3e4a2D4609309A837DF653Cbd71b1589bb2E65',
				privateKey: '0xd20ac7cb8e3a8c9e655fa729f4e6d836717233874a8722bf92097b102576c4e2',
				name: 'Arkadiy',
				notes: 'Testing profile',
			},
			{
				address: '0xAC31746448cdcC7e72915F68185372FF63a10279',
				privateKey: '0x4a06275ea3f9d5bb57b72b2c6d59fdbc12dbf00fd1d1ef6e2df7040b705333c5',
				name: 'Sergey',
				notes: 'Preview profile',
			},
			{
				address: '0xad145e1F9684f926996Bfe9d967c4E3bF55d35a3',
				privateKey: '0xed0c62a9c2d2f8968ad14fb00a486653bae207cba2109720288912f065cc1e91',
				name: 'Test1',
				notes: 'wefwf',
			},
		]);

		const logout = async () => {
			await closeSpace();
			await encryptionManager.disconnect();
			clearLockKeyCache();
			account.value = null;
			Object.assign(accountInfo, {});
			contacts.length = 0;
			transactions.value = [];
			space.value = null;
		};

		const updateVault = async () => {
			//const idx = vaults.value.findIndex((v) => v.address === account.value.address);
			//if (idx > -1) vaults.value[idx] = account.value;
		};

		const createSpace = async () => {
			try {
				space.value = await dxClient.value.spaces.create({ role: SpaceMember.Role.ADMIN }); //, encryptionKey: $user.account.metaPrivateKey
				account.value.spaceId = space.value.id;
				await encryptionManager.setData(toVaultFormat(account.value));
				console.log('User space created', account.value.spaceId);
			} catch (error) {
				console.log('createSpace error', error);
			}
		};

		const initializeAccountInfo = async (initialAccountInfo) => {
			const existingAccountInfo = await space.value.db.query((doc) => doc.type === 'accountInfo').run();

			if (existingAccountInfo.objects.length === 0) {
				const filteredAccountInfo = accountInfoKeys.reduce((acc, key) => {
					if (key in initialAccountInfo) {
						acc[key] = $enigma.encryptDataSync(initialAccountInfo[key], account.value.privateKey);
					}
					return acc;
				}, {});

				accountInfoDx = create(Expando, {
					...filteredAccountInfo,
					updatedAt: dayjs().valueOf(),
					type: 'accountInfo',
				});
				await space.value.db.add(accountInfoDx);
				Object.assign(accountInfo, $enigma.decryptObjectKeys(accountInfoDx, accountInfoKeys, account.value.privateKey));
				await encryptionManager.updateAccountInfoVault(accountInfo);

				console.log('✅ Initial accountInfo added to DXOS Space', accountInfo);
			} else {
				const latestAccountInfo = await mergeAccountInfoDuplicates(existingAccountInfo.objects);
				console.log('ℹ️ DXOS Space contains accountInfo', latestAccountInfo);
				Object.assign(accountInfo, latestAccountInfo);
			}
		};

		let contactUnsubscribe, isContactsUpdating, accountInfoUnsubscribe, isAccountInfoUpdating, backupsUnsubscribe, isBackupsUpdating;
		const openSpace = async (initialAccountInfo) => {
			try {
				await space.value.waitUntilReady();
				const accountInfoQuery = space.value.db.query((doc) => doc.type === 'accountInfo');
				let existingAccountInfo = await accountInfoQuery.run();

				if (existingAccountInfo.objects.length === 0) {
					await initializeAccountInfo(initialAccountInfo);
				} else {
					accountInfoDx = await mergeAccountInfoDuplicates(existingAccountInfo.objects);
					Object.assign(accountInfo, $enigma.decryptObjectKeys(accountInfoDx, accountInfoKeys, account.value.privateKey));
					await encryptionManager.updateAccountInfoVault(accountInfo);
				}

				accountInfoUnsubscribe = accountInfoQuery.subscribe(async ({ objects }) => {
					try {
						accountInfoDx = await mergeAccountInfoDuplicates(objects);
						Object.assign(accountInfo, $enigma.decryptObjectKeys(accountInfoDx, accountInfoKeys, account.value.privateKey));
						await encryptionManager.updateAccountInfoVault(accountInfo);
					} catch (error) {
						console.log('-------accountInfo update------- error', error);
					}
				});
			} catch (error) {
				console.log('openSpace error', error);
			}

			try {
				const contactsQuery = space.value.db.query((doc) => doc.type === 'contact');
				const existingContacts = await contactsQuery.run();

				const cd = await mergeContactsDuplicates(existingContacts.objects);
				contactsDx.splice(0, contactsDx.length, ...cd);
				//console.log(
				//	'-------contactsDx------- ',
				//	cd.map((contact) => contactKeys.map((k) => console.log(contact[k]))),
				//);
				contacts.splice(0, contacts.length, ...cd.map((contact) => $enigma.decryptObjectKeys(contact, contactKeys, account.value.privateKey)));
				contactUnsubscribe = contactsQuery.subscribe(async ({ objects }) => {
					try {
						const cd = await mergeContactsDuplicates(objects);
						//console.log(
						//	'-------contactsDx------- subscribe',
						//	cd.map((contact) => contactKeys.map((k) => contact[k])),
						//);
						contactsDx.splice(0, contactsDx.length, ...cd);
						contacts.splice(0, contacts.length, ...cd.map((contact) => $enigma.decryptObjectKeys(contact, contactKeys, account.value.privateKey)));
					} catch (error) {
						console.log('-------contacts update------- error', error);
					}
				});
			} catch (error) {
				console.log('openSpace error', error);
			}

			try {
				const backupsQuery = space.value.db.query((doc) => doc.type === 'backup');
				const existingBackups = await backupsQuery.run();

				const cd = await mergeBackupsDuplicates(existingBackups.objects);
				backupsDx.splice(0, backupsDx.length, ...cd);
				//console.log(
				//	'-------contactsDx------- ',
				//	cd.map((contact) => contactKeys.map((k) => console.log(contact[k]))),
				//);
				//contacts.splice(0, contacts.length, ...cd.map((contact) => $enigma.decryptObjectKeys(contact, contactKeys, account.value.privateKey)));
				backupsUnsubscribe = backupsQuery.subscribe(async ({ objects }) => {
					try {
						const cd = await mergeBackupsDuplicates(objects);
						//console.log(
						//	'-------contactsDx------- subscribe',
						//	cd.map((contact) => contactKeys.map((k) => contact[k])),
						//);
						backupsDx.splice(0, backupsDx.length, ...cd);
						//contacts.splice(0, contacts.length, ...cd.map((contact) => $enigma.decryptObjectKeys(contact, contactKeys, account.value.privateKey)));
					} catch (error) {
						console.log('-------backups update------- error', error);
					}
				});
			} catch (error) {
				console.log('openSpace backups error', error);
			}
		};

		const closeSpace = async () => {
			if (accountInfoUnsubscribe) accountInfoUnsubscribe();
			if (contactUnsubscribe) contactUnsubscribe();
			if (backupsUnsubscribe) backupsUnsubscribe();

			//try {
			//	console.log('space.value', space.value);
			//	space.value.disconnect(); // Ensure clean disconnection
			//} catch (error) {
			//	console.log('closeSpace error', error);
			//}
		};

		const mergeContactsDuplicates = async (contactsList) => {
			try {
				const contactMap = new Map();
				const duplicates = [];
				contactsList.forEach((contact) => {
					if (!contactMap.has(contact.publicKey)) {
						contactMap.set(contact.publicKey, contact);
					} else {
						// Conflict detected: Two contacts with the same publicKey exist
						const existing = contactMap.get(contact.publicKey);
						// Keep the latest updated version
						if (contact.updatedAt > existing.updatedAt) {
							duplicates.push(existing); // Mark the older contact for deletion
							contactMap.set(contact.publicKey, contact);
						} else {
							duplicates.push(contact); // Mark the newer one as a duplicate
						}
					}
				});
				// Prevent Infinite Loop: Only update DB if duplicates exist
				if (duplicates.length > 0 && !isContactsUpdating) {
					isContactsUpdating = true; // Lock updates
					// Remove duplicates from DXOS
					try {
						for (const duplicate of duplicates) {
							await space.value.db.remove(duplicate);
						}
					} catch (error) {
						console.log('mergeContactsDuplicates space.value.db.remove error', error);
					}

					isContactsUpdating = false; // Unlock updates
				}
				return Array.from(contactMap.values()); // Return the merged list
			} catch (error) {
				console.log('mergeContactsDuplicates error', error);
				return [];
			}
		};

		const mergeAccountInfoDuplicates = async (docs) => {
			try {
				if (docs.length === 0) return null; // No accountInfo found
				// Find the most recent accountInfo
				let latestAccountInfo = docs[0];
				for (const doc of docs) {
					if (doc.updatedAt > latestAccountInfo.updatedAt) {
						latestAccountInfo = doc;
					}
				}
				// Remove older duplicates from DXOS
				const duplicates = docs.filter((doc) => doc.id !== latestAccountInfo.id);
				// Prevent Infinite Loop: Only update DB if duplicates exist
				if (duplicates.length > 0 && !isAccountInfoUpdating) {
					isAccountInfoUpdating = true; // Start update process
					// Remove duplicates from DXOS
					for (const duplicate of duplicates) {
						await space.value.db.remove(duplicate);
					}
					isAccountInfoUpdating = false; // Reset flag after update
				}
				await encryptionManager.updateAccountInfoVault(latestAccountInfo);
				return latestAccountInfo;
			} catch (error) {
				console.log('mergeAccountInfoDuplicates error', error);
				return null;
			}
		};

		const mergeBackupsDuplicates = async (list) => {
			try {
				const backupsMap = new Map();
				const duplicates = [];
				list.forEach((backup) => {
					if (!backupsMap.has(backup.tag)) {
						backupsMap.set(backup.tag, backup);
					} else {
						// Conflict detected: Two backups with the same publicKey exist
						const existing = backupsMap.get(backup.tag);
						// Keep the latest updated version
						if (backup.updatedAt > existing.updatedAt) {
							duplicates.push(existing); // Mark the older backup for deletion
							backupsMap.set(backup.tag, backup);
						} else {
							duplicates.push(backup); // Mark the newer one as a duplicate
						}
					}
				});
				// Prevent Infinite Loop: Only update DB if duplicates exist
				if (duplicates.length > 0 && !isBackupsUpdating) {
					isBackupsUpdating = true; // Lock updates
					// Remove duplicates from DXOS
					try {
						for (const duplicate of duplicates) {
							await space.value.db.remove(duplicate);
						}
					} catch (error) {
						console.log('mergeBackupsDuplicates space.value.db.remove error', error);
					}

					isBackupsUpdating = false; // Unlock updates
				}
				return Array.from(backupsMap.values()); // Return the merged list
			} catch (error) {
				console.log('mergeBackupsDuplicates error', error);
				return [];
			}
		};

		watch(
			accountInfo,
			async (newAccountInfo) => {
				//console.log('watch accountInfo', newAccountInfo);
				if (!accountInfoDx || !account.value) return;
				const hasChanges = accountInfoKeys.some((key) => newAccountInfo[key] !== $enigma.decryptDataSync(accountInfoDx[key], account.value.privateKey));
				if (hasChanges) {
					//console.log('✅ Changes detected, updating DXOS object');
					accountInfoKeys.forEach((key) => {
						accountInfoDx[key] = $enigma.encryptDataSync(newAccountInfo[key], account.value.privateKey);
					});
					accountInfoDx.updatedAt = dayjs().valueOf();
					console.log('✨ Updated DXOS object', accountInfoDx.id);
				} else {
					//console.log('⚡ No changes detected');
				}
			},
			{ deep: true },
		);
		//watch(
		//	contacts,
		//	async (newContacts) => {
		//		//console.log('watch accountInfo', newAccountInfo);
		//		if (!contactsDx || !account.value) return;
		//		const hasChanges = contactKeys.some((key) => newContacts[key] !== $enigma.decryptDataSync(accountInfoDx[key], account.value.privateKey));
		//		if (hasChanges) {
		//			//console.log('✅ Changes detected, updating DXOS object');
		//			accountInfoKeys.forEach((key) => {
		//				accountInfoDx[key] = $enigma.encryptDataSync(newAccountInfo[key], account.value.privateKey);
		//			});
		//			accountInfoDx.updatedAt = dayjs().valueOf();
		//			console.log('✨ Updated DXOS object', accountInfoDx.id);
		//		} else {
		//			//console.log('⚡ No changes detected');
		//		}
		//	},
		//	{ deep: true },
		//);
		//newAccountInfo.updatedAt = dayjs().valueOf()
		//watch(
		//	contacts,
		//	async (newContacts) => {
		//		console.log('watch contacts', newContacts);
		//		for (const contact of newContacts) {
		//			await space.db.update(contact);
		//		}
		//	},
		//	{ deep: true },
		//);

		const addContact = async (contact) => {
			const newContact = {
				...contact,
				updatedAt: dayjs().valueOf(),
				type: 'contact',
			};
			await space.value.db.add(newContact);
		};

		const initializeContacts = async (initialContacts) => {
			const existingContacts = await space.value.db.query((doc) => doc.type === 'contact').run();
			if (existingContacts.objects.length === 0) {
				// If there are no contacts, add all initial contacts
				for (const contact of initialContacts) {
					const contactDx = create(Expando, {
						...contact,
						updatedAt: dayjs().valueOf(),
						type: 'contact',
					});
					await space.value.db.add(contactDx);
					contacts.value.push(contactDx);
				}
				console.log('✅ Initial contacts added to DXOS Space!');
			} else {
				console.log('ℹ️ DXOS Space already contains contacts. Checking for missing ones...');
				// Create a Set of existing contact publicKeys for quick lookup
				const existingKeys = new Set(existingContacts.results.map((contact) => contact.publicKey));
				// Find missing contacts and add only those
				const missingContacts = initialContacts.filter((contact) => !existingKeys.has(contact.publicKey));
				if (missingContacts.length > 0) {
					for (const contact of missingContacts) {
						await space.value.db.add(contact);
					}
					console.log(`✅ Added ${missingContacts.length} missing contacts.`);
				} else {
					console.log('✅ No missing contacts. Everything is up to date.');
				}
			}
		};

		const toVaultFormat = (user) => {
			return {
				privateKey: user.privateKey,
				spaceId: user.spaceId,
			};
			return [
				[user.name, $enigma.combineKeypair(user.privateKeyB64, user.publicKeyB64)],
				user.rooms,
				user.contacts.reduce((acc, u) => {
					acc[u.publicKey] = { name: u.name, notes: u.notes, avatar: u.avatar };
					return acc;
				}, {}),
			];
		};

		const fromVaultFormat = async (vault) => {
			return {
				...(await generateAccount(vault.privateKey)),
				spaceId: vault.spaceId,
			};
			const keys = $enigma.splitKeypair(vault[0][1]);
			const privateKeyHex = '0x' + $enigma.convertPrivateKeyToHex(keys.privateKey);
			const publicKeyHex = '0x' + $enigma.convertPrivateKeyToHex(keys.publicKey);
			const wallet = new Wallet(privateKeyHex);
			const signature = await wallet.signMessage(privateKeyHex);
			const meta = await web3Store().bukitupClient.generateKeysFromSignature(signature);

			return {
				displayName: vault[0][0],
				address: wallet.address,
				metaPrivateKey: meta.spendingKeyPair.privatekey,
				metaPublicKey: meta.spendingKeyPair.account.publicKey,
				privateKey: privateKeyHex,
				privateKeyB64: keys.privateKey,
				publicKey: publicKeyHex,
				publicKeyB64: keys.publicKey,
				contacts: Object.entries(vault[2]).map(([publicKey, value]) => ({
					publicKey,
					address: utils.computeAddress('0x' + publicKey).toLowerCase(),
					...value,
				})),
				rooms: vault[1],
			};
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
				const account = {
					address: wallet.address,
					privateKey: privateKeyHex,
					privateKeyB64,
					publicKey: publicKeyHex,
					publicKeyB64,
					metaPublicKey: meta.spendingKeyPair.account.publicKey,
					metaPrivateKey: meta.spendingKeyPair.privatekey,
				};
				//console.log('generateAccount', JSON.stringify(account, null, 2));
				return account;
			} catch (error) {
				console.log('generateAccount error', error);
			}
		};

		async function clearIndexedDB() {
			return new Promise((resolve, reject) => {
				let databases = indexedDB.databases();
				databases.then((dbs) => {
					let deletions = dbs.map((db) => indexedDB.deleteDatabase(db.name));
					//deletions.push(db.createObjectStore('keyval', { keyPath: 'id' }));
					Promise.all(deletions).then(resolve).catch(reject);
				});
			});
		}

		return {
			vaults,
			logout,

			account,
			accountInfo,
			contacts,
			contactsDx,

			defaultAvatar,

			transactions,
			toVaultFormat,
			fromVaultFormat,
			generateAccount,
			updateVault,

			dxClient,
			space,
			createSpace,
			openSpace,
			closeSpace,
			initializeAccountInfo,
			initializeContacts,

			setEncryptionManager,
			clearIndexedDB,
			accountInfoKeys,
			contactKeys,

			backupsDx,
			backupKeys,
		};
	},
	//{
	//	persist: {
	//		//storage: piniaPluginPersistedstate.localStorage(),
	//		pick: ['vaults'],
	//	},
	//},
);
