import { connect, rawStorage, removeAll } from "@lo-fi/local-vault";
import "@lo-fi/local-vault/adapter/idb";

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
   #abortController = new AbortController(); // Controller for canceling operations

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
            },
            signal: this.#abortController.signal,
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
            storageType: "idb",
            signal: this.#abortController.signal,
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
         await this.#vault.set(vaultID, value, {
            signal: this.#abortController.signal,
         });
         // console.log(`Data saved: key = "${vaultID}", value = "${value}"`);
         return true;
      } catch (error) {
         await this.handleError(error, "Error saving data");
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
         const value = await this.#vault.get(vaultID, {
            signal: this.#abortController.signal,
         });
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
      return await this.#rawStore.get("vault-id");
   }

   /**
    * Saves the vault ID to raw storage.
    * @param {string} id - The vault ID.
    */
   async saveVaultID(id) {
      await this.#rawStore.set("vault-id", id);
   }

   /**
    * Removes the vault ID from raw storage.
    */
   async removeVaultID() {
      await this.#rawStore.remove("vault-id");
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

   /**
    * Cancels the current operation with a specified reason.
    * @param {string} [reason="Operation canceled"] - The reason for canceling the operation.
    */
   cancelOperation(reason = "Operation canceled") {
      if (this.#abortController) {
         this.isAuth = false; // Use the setter
         this.#abortController.abort(reason);
         this.#abortController = new AbortController();
         console.warn(`Operation canceled: ${reason}`);
      }
   }
}
