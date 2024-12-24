import * as secp from "@noble/secp256k1";
import blf from "../vendor/blowfish";
import jsSHA from "jssha/dist/sha3";
import { Buffer } from "buffer";

export class Enigma {
   /**
    * Hashes data using SHA3-256.
    * @param {string} base64Data - Data in base64 format.
    * @returns {string} - Hashed data in base64 format.
    */
   hash(base64Data) {
      const shaObj = new jsSHA("SHA3-256", "B64");
      shaObj.update(base64Data);
      return shaObj.getHash("B64");
   }

   /**
    * Encrypts data using Blowfish in CFB mode.
    * @param {string} base64PlainData - Plain data in base64 format.
    * @param {string} base64Password - Password in base64 format.
    * @returns {string} - Encrypted data in base64 format.
    */
   encryptData(base64PlainData, base64Password) {
      const { pass, iv } = this.#deriveKeyAndIV(base64Password);
      const ciphered = this.#blowfishCFB(Buffer.from(base64PlainData, "base64"), pass, iv, false);
      return ciphered.toString("base64");
   }

   /**
    * Decrypts data using Blowfish in CFB mode.
    * @param {string} base64CipheredData - Encrypted data in base64 format.
    * @param {string} base64Password - Password in base64 format.
    * @returns {string} - Decrypted data in base64 format.
    */
   decryptData(base64CipheredData, base64Password) {
      const { pass, iv } = this.#deriveKeyAndIV(base64Password);
      const deciphered = this.#blowfishCFB(Buffer.from(base64CipheredData, "base64"), pass, iv, true);
      return deciphered.toString("base64");
   }

   /**
    * Generates a keypair for ECDH.
    * @returns {Object} - Object containing the public and private keys in base64 format.
    */
   generateKeypair() {
      const privateKey = secp.utils.randomPrivateKey();
      const publicKey = secp.getPublicKey(privateKey, true);

      return {
         publicKey: this.arrayToBase64(publicKey),
         privateKey: this.arrayToBase64(privateKey),
      };
   }

   /**
    * Computes a shared secret using ECDH.
    * @param {string} base64PrivateKey - Private key in base64 format.
    * @param {string} base64PublicKey - Public key in base64 format.
    * @returns {string} - Shared secret in base64 format.
    */
   computeSharedSecret(base64PrivateKey, base64PublicKey) {
      const privateKeyArray = this.base64ToArray(base64PrivateKey);
      const publicKeyArray = this.base64ToArray(base64PublicKey);
      const sharedSecret = secp.getSharedSecret(privateKeyArray, publicKeyArray, true);

      return this.arrayToBase64(sharedSecret);
   }

   /**
    * Encrypts data using a shared secret.
    * @param {string} base64PlainData - Plain data in base64 format.
    * @param {string} base64PrivateKey - Private key in base64 format.
    * @param {string} base64PublicKey - Public key in base64 format.
    * @returns {string} - Encrypted data in base64 format.
    */
   encryptWithSharedSecret(base64PlainData, base64PrivateKey, base64PublicKey) {
      const sharedSecret = this.computeSharedSecret(base64PrivateKey, base64PublicKey);
      return this.encryptData(base64PlainData, sharedSecret);
   }

   /**
    * Creates a shortcode from a full key.
    * @param {string} base64FullKey - Full key in base64 format.
    * @returns {string} - Shortcode in hexadecimal format.
    */
   shortcodeFromFullKey(base64FullKey) {
      const buffer = Buffer.from(base64FullKey, "base64");
      const publicKey = Buffer.from(new Uint8Array(buffer.buffer, 32, 33)).toString("base64");
      const publicHash = this.hash(publicKey);
      const hashBuffer = Buffer.from(publicHash, "base64");
      const code = Buffer.from(new Uint8Array(hashBuffer.buffer, 0, 3));

      return code.toString("hex");
   }

   /**
    * Combines private and public keys into a single Base64-encoded string.
    * @param {string} privateKeyB64 - Private key in base64 format.
    * @param {string} publicKeyB64 - Public key in base64 format.
    * @returns {string} - Combined key in base64 format.
    */
   combineKeypair(privateKeyB64, publicKeyB64) {
      const combined = new Uint8Array(32 + 33);
      const privateKeyArray = this.base64ToArray(privateKeyB64);
      const publicKeyArray = this.base64ToArray(publicKeyB64);

      combined.set(privateKeyArray, 0);
      combined.set(publicKeyArray, 32);

      return this.arrayToBase64(combined);
   }

   /**
    * Splits a combined key (Base64) back into private and public keys.
    * @param {string} combinedKeyBase64 - Combined key in base64 format.
    * @returns {Object} - Object containing `privateKey` and `publicKey` in base64 format.
    */
   splitKeypair(combinedKeyBase64) {
      const combinedArray = this.base64ToArray(combinedKeyBase64);

      const privateKeyArray = combinedArray.slice(0, 32);
      const publicKeyArray = combinedArray.slice(32);

      const privateKeyBase64 = this.arrayToBase64(privateKeyArray);
      const publicKeyBase64 = this.arrayToBase64(publicKeyArray);

      return {
         privateKey: privateKeyBase64,
         publicKey: publicKeyBase64,
      };
   }

   // Private methods and properties

   /**
    * Derives a key and initialization vector (IV) from a password.
    * @param {string} base64Password - Password in base64 format.
    * @returns {Object} - Object containing the key and initialization vector.
    */
   #deriveKeyAndIV(base64Password) {
      const passBuffer = Buffer.from(base64Password, "base64");
      const pass = passBuffer.slice(8, 24); // 16 bytes for the key
      const key1 = passBuffer.slice(0, 8); // First 8 bytes
      const key2 = passBuffer.slice(24, 32); // Last 8 bytes

      const iv = Buffer.alloc(8);
      for (let i = 0; i < 8; i++) {
         iv[i] = key1[i] ^ key2[i]; // Generate IV using XOR
      }

      return { pass, iv };
   }

   /**
    * Implements Blowfish encryption/decryption in CFB mode.
    * @param {Buffer} data - Data to process.
    * @param {Buffer} key - Key for Blowfish.
    * @param {Buffer} iv - Initialization vector.
    * @param {boolean} decrypt - Flag indicating decryption.
    * @returns {Buffer} - Processed data.
    */
   #blowfishCFB(data, key, iv, decrypt = false) {
      const context = blf.key(key);
      return blf.cfb(context, iv, data, decrypt);
   }

   // Utility methods for data conversion

   /**
    * Converts base64 data to a string.
    * @param {string} base64Data - Data in base64 format.
    * @returns {string} - Decoded string.
    */
   base64ToString(base64Data) {
      return Buffer.from(base64Data, "base64").toString("utf-8");
   }

   /**
    * Converts base64 data to a Uint8Array.
    * @param {string} base64Data - Data in base64 format.
    * @returns {Uint8Array} - Byte array.
    */
   base64ToArray(base64Data) {
      const buffer = Buffer.from(base64Data, "base64");
      return new Uint8Array(buffer.buffer, buffer.byteOffset, buffer.byteLength);
   }

   /**
    * Converts a Uint8Array to a base64 string.
    * @param {Uint8Array} array - Byte array.
    * @returns {string} - Data in base64 format.
    */
   arrayToBase64(array) {
      return Buffer.from(array).toString("base64");
   }

   /**
    * Converts a string to a base64 string.
    * @param {string} string - Original string.
    * @returns {string} - Data in base64 format.
    */
   stringToBase64(string) {
      return Buffer.from(string, "utf-8").toString("base64");
   }

   /**
    * Converts a public key from base64 to hexadecimal format.
    * @param {string} publicKeyBase64 - Public key in base64 format.
    * @returns {string} - Public key in hexadecimal format.
    */
   convertPublicKeyToHex(publicKeyBase64) {
      const publicKeyArray = this.base64ToArray(publicKeyBase64);
      return Buffer.from(publicKeyArray).toString("hex");
   }

   /**
    * Converts a private key from base64 to hexadecimal format.
    * @param {string} privateKeyBase64 - Private key in base64 format.
    * @returns {string} - Private key in hexadecimal format.
    */
   convertPrivateKeyToHex(privateKeyBase64) {
      const privateKeyArray = this.base64ToArray(privateKeyBase64);
      return Buffer.from(privateKeyArray).toString("hex");
   }
}
