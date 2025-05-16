import { connect, rawStorage, removeAll } from '@lo-fi/local-vault';
import '@lo-fi/local-vault/adapter/idb';
import { removeLocalAccount } from '@lo-fi/local-data-lock';

/**
 * Class for managing encryption and data storage.
 * Implements the Singleton pattern to ensure a single instance.
 * Added support for events via EventTarget.
 */
export class EncryptionManager extends EventTarget {
	// Static property to store the single instance of the class
	static instance = null;

	// Private properties
	#vault = null; // Storage object
	#vaults = [];
	#isAuth = false; // Authorization state flag
	#rawStore = rawStorage('idb'); // Raw storage for storing the vault ID
	#isProduction = false;
	/**
	 * Private constructor to implement Singleton.
	 * Use EncryptionManager.getInstance() to get the instance.
	 */
	constructor(IS_PRODUCTION) {
		super();
		if (EncryptionManager.instance) {
			return EncryptionManager.instance;
		}
		EncryptionManager.instance = this;

		this.#isProduction = IS_PRODUCTION;

		this.getVaults();
	}

	/**
	 * Static method to get the single instance of the class.
	 * @returns {EncryptionManager} - Instance of the EncryptionManager class.
	 */
	static getInstance() {
		if (!EncryptionManager.instance) {
			EncryptionManager.instance = new EncryptionManager();
		}
		return EncryptionManager.instance;
	}

	/**
	 * Getter for accessing the authorization state.
	 * @returns {boolean} - Authorization state (true or false).
	 */
	get isAuth() {
		return this.#isAuth;
	}

	/**
	 * Setter for updating the authorization state.
	 * Automatically dispatches an authChange event when the value changes.
	 * @param {boolean} value - New value for the authorization state.
	 */
	set isAuth(value) {
		if (this.#isAuth !== value) {
			// Check if the value has changed
			this.#isAuth = value;
			this.dispatchEvent(new CustomEvent('authChange', { detail: { isAuth: value } }));
		}
	}

	/**
	 * Initializes the storage by connecting to an existing vault or creating a new one.
	 */
	async initialize() {
		try {
			const vaultID = await this.getVaultID();
			if (vaultID) {
				await this.connectToVault(vaultID);
			} else {
				await this.createVault();
			}
		} catch (error) {
			await this.handleError(error, 'Error during storage initialization');
		}
	}

	/**
	 * Creates a new vault and saves its ID.
	 */
	async createVault(data) {
		if (this.#isProduction) {
			this.#vault = await connect({
				storageType: 'idb',
				addNewVault: true,
				keyOptions: data.keyOptions,
			});
			//await this.saveVaultID(this.#vault.id);
			this.#vaults.push({
				name: data.keyOptions?.username,
				notes: data.notes,
				avatar: data.avatar,
				address: data.address,
				publicKey: data.publicKey,
				vaultId: this.#vault.id,
			});
			// await this.#vault.set(vaultID ? vaultID : this.#vault.id, value);
			await this.#rawStore.set('vaults-registry', this.#vaults);
		} else {
			this.#vault = {
				id: data.publicKey,
			};

			this.#vaults.push({
				name: data.keyOptions.username,
				address: data.address,
				notes: data.notes,
				avatar: data.avatar,
				publicKey: data.publicKey,
				vaultId: this.#vault.id,
			});

			await this.#rawStore.set('test-vaults-registry', this.#vaults);
		}

		// Set isAuth using the setter
		this.isAuth = true;

		console.log('Created a new vault with ID:', this.#vault.id);

		this.setCurrentUser(true);
	}

	/**
	 * Connects to an existing vault using its ID.
	 * @param {string} vaultID - The vault identifier.
	 */
	async connectToVault(vaultID) {
		try {
			if (this.#isProduction) {
				this.#vault = await connect({
					vaultID,
					storageType: 'idb',
				});
			} else {
				this.#vault = {
					id: vaultID,
				};
			}

			// Set isAuth using the setter
			this.isAuth = true;

			console.log('Connected to existing vault:', vaultID);

			this.setCurrentUser(true);
		} catch (error) {
			this.isAuth = false; // Use the setter
			console.error(error);
		}
	}

	async disconnect() {
		if (this.#vault) {
			await this.setCurrentUser(false);
		}
		this.#vault = null;
		this.isAuth = false;
	}

	async removeVault(id) {
		if (!id) id = this.#vault.id;
		try {
			const vaults = this.#vaults.filter((item) => item.vaultId !== id);

			if (this.#isProduction) {
				const vaultData = await this.#rawStore.get(`local-vault-${id}`);
				await this.#vault.clear();
				removeLocalAccount(vaultData.accountID);
				await this.#rawStore.set('vaults-registry', vaults);
			} else {
				await this.#rawStore.remove(`test-local-vault-${id}`);
				await this.#rawStore.set('test-vaults-registry', vaults);
			}

			this.#vaults = vaults;

			this.#vault = null;
			this.isAuth = false;
			await this.removeVaultID();
		} catch (error) {
			console.error('removeVault error', error);
		}
	}

	/**
	 * Saves data to the vault.
	 * @param {string} value - Data to save.
	 */
	async setData(value) {
		try {
			//await this.ensureVault();
			//const vaultID = await this.getVaultID();
			if (this.#isProduction) {
				await this.#vault.set(this.#vault.id, value);
			} else {
				await this.#rawStore.set(`test-local-vault-${this.#vault.id}`, value);
			}

			return true;
		} catch (error) {
			await this.handleError(error, 'Error saving data');
		}
	}

	async getVaults() {
		try {
			let vaults;
			if (this.#isProduction) {
				vaults = await this.#rawStore.get('vaults-registry');
			} else {
				vaults = await this.#rawStore.get('test-vaults-registry');
			}

			this.#vaults = vaults || [];
			return this.#vaults;
		} catch (error) {
			this.handleError(error, 'no vaults');
			console.error(`getVaults error`, error);
			return [];
		}
	}

	async updateAccountInfoVault(accountInfo) {
		try {
			const registryKey = this.#isProduction ? 'vaults-registry' : 'test-vaults-registry';
			const vaults = await this.#rawStore.get(registryKey);
			const idx = vaults.findIndex((v) => v.vaultId === this.#vault.id);
			if (idx > -1) {
				vaults[idx].name = accountInfo.name;
				vaults[idx].notes = accountInfo.notes;
				vaults[idx].avatar = accountInfo.avatar;
				await this.#rawStore.set(registryKey, vaults);
				this.#vaults = vaults;
			}
		} catch (error) {
			this.handleError(error, 'no vaults');
			console.error(`getVaults error`, error);
		}
	}

	async setCurrentUser(isSet) {
		try {
			const registryKey = this.#isProduction ? 'vaults-registry' : 'test-vaults-registry';
			const vaults = await this.#rawStore.get(registryKey);
			console.log('setCurrentUser', isSet, vaults, this.#vault);
			const updatedVaults = vaults.map((vault) => {
				const isCurrent = vault.vaultId === this.#vault.id;
				return {
					...vault,
					current: isCurrent && isSet,
				};
			});
			await this.#rawStore.set(registryKey, updatedVaults);
			await (isSet ? this.saveVaultID(this.#vault.id) : this.removeVaultID());
			this.#vaults = updatedVaults;
		} catch (error) {
			await this.handleError(error, 'Error retrieving data');
		}
	}

	/**
	 * Retrieves data from the vault.
	 * @returns {Promise<any>} - Retrieved data.
	 */
	async getData() {
		try {
			let data;
			if (this.#isProduction) {
				data = await this.#vault.get(this.#vault.id);
			} else {
				data = await this.#rawStore.get(`test-local-vault-${this.#vault.id}`);
			}
			return data;
		} catch (error) {
			await this.handleError(error, 'Error retrieving data');
		}
	}

	/**
	 * Checks for the existence of a vault.
	 * @returns {Promise<boolean>} - true if the vault exists, otherwise false.
	 */
	async hasVault() {
		try {
			const vaultID = await this.getVaultID();
			return !!vaultID;
		} catch (error) {
			console.error('Error checking vault existence:', error);
			return false;
		}
	}

	/**
	 * Clears the vault and removes its ID.
	 */
	async clearVault() {
		try {
			await removeAll();
			await this.removeVaultID();
			this.#vault = null;

			// Set isAuth using the setter
			this.isAuth = false;

			console.log('Vault cleared');
		} catch (error) {
			console.error('Error clearing the vault:', error);
		}
	}

	/**
	 * Retrieves the vault ID from raw storage.
	 * @returns {Promise<string|null>} - The vault ID or null if not found.
	 */
	async getVaultID() {
		return await this.#rawStore.get('vault-id');
	}

	/**
	 * Saves the vault ID to raw storage.
	 * @param {string} id - The vault ID.
	 */
	async saveVaultID(id) {
		await this.#rawStore.set('vault-id', id);
	}

	/**
	 * Removes the vault ID from raw storage.
	 */
	async removeVaultID() {
		await this.#rawStore.remove('vault-id');
	}

	/**
	 * Ensures the vault is initialized if it hasn't been already.
	 */
	async ensureVault() {
		if (!this.#vault) {
			console.warn('Vault not initialized. Initializing...');
			await this.initialize();
		}
	}

	/**
	 * Handles errors that occur during storage operations.
	 * @param {Error} error - The error object.
	 * @param {string} message - The message to display.
	 */
	async handleError(error, message) {
		this.isAuth = false; // Use the setter
		if (this.isCancelError(error)) {
			console.warn(`${message}: Operation canceled by user. Clearing the vault.`);
			await this.clearVault();
		} else {
			console.error(`${message}:`, error);
		}
	}

	/**
	 * Checks if an error resulted from a canceled operation.
	 * @param {Error} error - The error object.
	 * @returns {boolean} - true if the operation was canceled, otherwise false.
	 */
	isCancelError(error) {
		return (
			error.message?.includes('The operation either timed out or was not allowed') ||
			error.message?.includes('Credential auth failed') ||
			error.message?.includes('Identity/Passkey registration failed') ||
			error.name === 'AbortError'
		);
	}
}
