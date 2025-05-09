import { connect, rawStorage, removeAll } from "@lo-fi/local-vault";
import "@lo-fi/local-vault/adapter/idb";
import { fullKeyBase64ToPublicKeyHex } from "./enigma-functional";
import { computeAddress } from "ethers";
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
   #isAuth = false; // Authorization state flag
   #rawStore = rawStorage("idb"); // Raw storage for storing the vault ID

   /**
    * Private constructor to implement Singleton.
    * Use EncryptionManager.getInstance() to get the instance.
    */
   constructor() {
      super();
      if (EncryptionManager.instance) {
         return EncryptionManager.instance;
      }
      EncryptionManager.instance = this;
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
         this.dispatchEvent(new CustomEvent("authChange", { detail: { isAuth: value } }));
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
         await this.handleError(error, "Error during storage initialization");
      }
   }

   /**
    * Creates a new vault and saves its ID.
    */
   async createVault() {
      try {
         this.#vault = await connect({
            storageType: "idb",
            addNewVault: true,
            keyOptions: {
               username: "biometric-user",
               displayName: "Biometric User",
            }
         });
         await this.saveVaultID(this.#vault.id);

         // Set isAuth using the setter
         this.isAuth = true;

         console.log("Created a new vault with ID:", this.#vault.id);
      } catch (error) {
         await this.handleError(error, "Error creating a new vault");
      }
   }

   /**
    * Connects to an existing vault using its ID.
    * @param {string} vaultID - The vault identifier.
    */
   async connectToVault(vaultID) {
      try {
         this.#vault = await connect({
            vaultID,
            storageType: "idb"
         });

         // Set isAuth using the setter
         this.isAuth = true;

         console.log("Connected to existing vault:", vaultID);
      } catch (error) {
         this.isAuth = false; // Use the setter
         console.error(error);
      }
   }

   /**
    * Saves data to the vault.
    * @param {string} value - Data to save.
    */
   async setData(value) {
      try {
         await this.ensureVault();
         const vaultID = await this.getVaultID();
         await this.#vault.set(vaultID, value);
         const me = JSON.parse(value)[0];
         const name = me[0];
         const fullKeyBase64 = me[1];
         const publicKeyHex = fullKeyBase64ToPublicKeyHex(fullKeyBase64);
         await this.updateVaultsRegistryEntry(vaultID, name, publicKeyHex);
         // console.log(`Data saved: key = "${vaultID}", value = "${value}"`);
         return true;
      } catch (error) {
         await this.handleError(error, "Error saving data");
      }
   }

   /**
    * Updates the vaults registry entry.
    * @param {string} vaultID - The vault ID.
    * @param {string} name - The name of the vault.
    * @param {string} publicKeyHex - The public key of the vault.
    */
   async updateVaultsRegistryEntry(vaultID, name, publicKeyHex) {
      try {
         let vaultsRegistry = await this.#rawStore.get("vaults-registry") || [];
         const existingVaultIndex = vaultsRegistry.findIndex(vault => vault.vaultId === vaultID);
         if (existingVaultIndex >= 0) {
            // rewrite name and pulicKey in existing vault
            vaultsRegistry[existingVaultIndex].name = name;
            vaultsRegistry[existingVaultIndex].publicKey = "0x" + publicKeyHex;
            vaultsRegistry[existingVaultIndex].address = this.ethAddressFromPublicKey(publicKeyHex);
         }
         await this.#rawStore.set("vaults-registry", vaultsRegistry);
      } catch (error) {
         console.error("Error updating vaults registry entry:", error);
      }
   }

   /**
    * Generates an Ethereum address from a public key using ethers.js.
    * @param {string} publicKeyHex - The public key in hex format.
    * @returns {string} - The Ethereum address.
    */
   ethAddressFromPublicKey(publicKeyHex) {
      try {
         // Ensure the public key has the '0x' prefix
         if (!publicKeyHex.startsWith('0x')) {
            publicKeyHex = '0x' + publicKeyHex;
         }
         
         // Check if ethers is properly loaded
         if (typeof computeAddress === 'undefined') {
            console.warn("Ethers.js library not properly loaded, falling back to simple address derivation");
            // Fallback to a simpler method if ethers.js is not available
           return undefined;
         }
         
         // Use ethers.js to compute the address
         const address = computeAddress(publicKeyHex);
         return address;
      } catch (error) {
         console.error("Error generating Ethereum address:", error);
         // Fallback in case of any error
         return undefined;
      }
   }

   /**
    * Retrieves data from the vault.
    * @returns {Promise<any>} - Retrieved data.
    */
   async getData() {
      try {
         await this.ensureVault();
         const vaultID = await this.getVaultID();
         const value = await this.#vault.get(vaultID);
         // console.log(`Data retrieved: key = "${vaultID}", value = "${value || "no data"}"`);
         return value;
      } catch (error) {
         await this.handleError(error, "Error retrieving data");
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
         console.error("Error checking vault existence:", error);
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

         console.log("Vault cleared.");
      } catch (error) {
         console.error("Error clearing the vault:", error);
      }
   }

   /**
    * Retrieves the vault ID from raw storage.
    * @returns {Promise<string|null>} - The vault ID or null if not found.
    */
   async getVaultID() {
      try {
         // First, check the vaults registry for a current vault
         const vaultsRegistry = await this.#rawStore.get("vaults-registry") || [];
         const currentVault = vaultsRegistry.find(vault => vault.current === true);
         
         if (currentVault && currentVault.vaultId) {
            console.log("Found current vault ID in vaults registry:", currentVault.vaultId);
            return currentVault.vaultId;
         }
         
         // Fall back to the original method if no current vault is found in the registry
         return await this.#rawStore.get("vault-id");
      } catch (error) {
         console.error("Error retrieving vault ID:", error);
         // Fall back to the original method if there's an error
         return await this.#rawStore.get("vault-id");
      }
   }

   /**
    * Saves the vault ID to raw storage.
    * @param {string} id - The vault ID.
    */
   async saveVaultID(id) {
      await this.#rawStore.set("vault-id", id);
      await this.updateVaultsRegistry(id);
   }

   /**
    * Updates the vaults registry when saving a vault ID.
    * @param {string} vaultId - The vault ID to set as current.
    */
   async updateVaultsRegistry(vaultId) {
      try {
         // Get the current vaults registry
         let vaultsRegistry = await this.#rawStore.get("vaults-registry") || [];
         
         // Find if the vault already exists in the registry
         const existingVaultIndex = vaultsRegistry.findIndex(vault => vault.vaultId === vaultId);
         
         if (existingVaultIndex >= 0) {
            // If vault exists, update its current status
            vaultsRegistry = vaultsRegistry.map(vault => ({
               ...vault,
               current: vault.vaultId === vaultId
            }));
         } else {
            // If vault doesn't exist, generate a new entry
            const newVault = {
               vaultId: vaultId,
               current: true,
               notes: "",
               createdAt: new Date().toISOString()
            };
            
            // Reset current status for all existing vaults
            vaultsRegistry = vaultsRegistry.map(vault => ({
               ...vault,
               current: false
            }));
            
            // Add the new vault to the registry
            vaultsRegistry.push(newVault);
         }
         
         // Save the updated vaults registry
         await this.#rawStore.set("vaults-registry", vaultsRegistry);
         console.log("Updated vaults registry with current vault:", vaultId);
      } catch (error) {
         console.error("Error updating vaults registry:", error);
      }
   }

   /**
    * Gets the vaults registry from raw storage.
    * @returns {Promise<Array>} - The vaults registry array or empty array if not found.
    */
   async getVaultsRegistry() {
      try {
         const vaultsRegistry = await this.#rawStore.get("vaults-registry");
         return vaultsRegistry || [];
      } catch (error) {
         console.error("Error retrieving vaults registry:", error);
         return [];
      }
   }

   /**
    * Removes the vault ID from raw storage.
    */
   async removeVaultID() {
      const vaultId = await this.getVaultID();
      await this.#rawStore.remove("vault-id");
      
      // Update the vaults registry to remove current status
      if (vaultId) {
         try {
            let vaultsRegistry = await this.#rawStore.get("vaults-registry");
            
            // Only proceed if vaults registry exists
            if (!vaultsRegistry) {
               console.log("Vaults registry doesn't exist, skipping update on logout");
               return;
            }
            
            // Remove current status from the logged out vault
            vaultsRegistry = vaultsRegistry.map(vault => {
               if (vault.vaultId === vaultId) {
                  return { ...vault, current: false };
               }
               return vault;
            });
            
            await this.#rawStore.set("vaults-registry", vaultsRegistry);
            console.log("Updated vaults registry on logout for vault:", vaultId);
         } catch (error) {
            console.error("Error updating vaults registry on logout:", error);
         }
      }
   }

   /**
    * Ensures the vault is initialized if it hasn't been already.
    */
   async ensureVault() {
      if (!this.#vault) {
         console.warn("Vault not initialized. Initializing...");
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
         error.message?.includes("The operation either timed out or was not allowed") ||
         error.message?.includes("Credential auth failed") ||
         error.message?.includes("Identity/Passkey registration failed") ||
         error.name === "AbortError"
      );
   }
}
