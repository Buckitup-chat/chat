import assert from 'assert';
import { getSharedSecret, ProjectivePoint, CURVE } from '@noble/secp256k1';
import { encryptWithPublicKey, cipher, decryptWithPrivateKey} from 'eth-crypto';
import { combine, split } from 'shamirs-secret-sharing';
import { keccak256, pad, toHex } from 'viem';
import { generatePrivateKey, privateKeyToAccount } from 'viem/accounts';

export const GENERATE_STEALTH_ADDRESS_MESSAGE = `Sign this message to generate your secret keys.

Make sure to sign this message only on a trusted website!

Your PIN: {pin}`;

/**
 * Class representing a stealth meta key pair.
 * Contains both the viewing and spending key pairs.
 */
export class StealthMetaKeyPair {
  /**
   * Create a StealthMetaKeyPair.
   * @param {string} viewingPrivateKey - The private key for viewing.
   * @param {string} spendingPrivateKey - The private key for spending.
   */
  constructor(viewingPrivateKey, spendingPrivateKey) {
    this.viewingKeyPair = new SingleKeyPair(viewingPrivateKey);
    this.spendingKeyPair = new SingleKeyPair(spendingPrivateKey);
  }
}

/**
 * Class representing a single key pair.
 * Contains the private key and its associated account.
 */
export class SingleKeyPair {
  
  /**
   * Create a SingleKeyPair.
   * @param {string} privateKey - The private key.
   */
  constructor(privateKey) {
    this.privatekey = privateKey;
    this.account = privateKeyToAccount(privateKey);
  }
}

export class BuckItUpClient {

  /* PUBLIC METHODS */
  /**
   * Generates a signature necessary to generate a StealthMetaKeyPair
   * @param pin {string} the salt of the signature
   * @param walletClient {WalletClient} the client connected
   */
  generateBaseSignature = async (pin, walletClient) => {
    assert(!!walletClient.account, 'Account not initialized in the WalletClient');
    assert(pin.length > 0, 'PIN must be present');
    const messageToSign = GENERATE_STEALTH_ADDRESS_MESSAGE.replace('{pin}', pin);
    return walletClient.signMessage({
      account: walletClient.account,
      message: messageToSign,
    });
  };

  /**
   * Returns a StealthMetaKeyPair given the signature to start with
   * @param signature {string} 0x padded and 64 bytes length signature
   */
  generateKeysFromSignature = async (signature) => {
    // Split hex string signature into two 32 byte chunks
    const startIndex = 2; // first two characters are 0x, so skip these
    const length = 64; // each 32 byte chunk is in hex, so 64 characters
    const portion1 = signature.slice(startIndex, startIndex + length);
    const portion2 = signature.slice(startIndex + length, startIndex + length + length);
    const lastByte = signature.slice(signature.length - 2);

    assert(`0x${portion1}${portion2}${lastByte}` === signature, 'Signature incorrectly generated or parsed');

    // Hash the signature pieces to get the two private keys
    const spendingPrivateKey = keccak256(`0x${portion1}`);
    const viewingPrivateKey = keccak256(`0x${portion2}`);

    // Create KeyPair instances from the private keys and return them
    return new StealthMetaKeyPair(spendingPrivateKey, viewingPrivateKey);
  };

  /* SSS methods */
  /**
   * Generate the shares for a given secret
   * @param secret
   * @param numShares
   * @param threshold
   */
  generateShares = (secret, numShares, threshold) => {
    const secretBuffer = Buffer.from(secret);
    const sharesBuffer = split(secretBuffer, { shares: numShares, threshold: threshold });
    return sharesBuffer.map(b => '0x' + b.toString('hex'));
  };

  /**
   * Generate the shares for a given secret, encrypted using the public keys passed.
   * The order of the returned secrets is the same as the order of the public keys passed
   * @param secret
   * @param numShares
   * @param threshold
   * @param publicKeys
   */
  generateSharesEncrypted = async (secret, numShares, threshold, publicKeys) => {
    assert(publicKeys.length === numShares, 'Number of shares and number of public keys do not match');
    const unencryptedShares = this.generateShares(secret, numShares, threshold);
    // Encrypt each share with its corresponding public key
    const encryptedShares = unencryptedShares.map((share, index) => {
      const publicKey = publicKeys[index];
      return encryptWithPublicKey(
        publicKey.slice(2),
        share,
      ).then(encrypted => '0x' + cipher.stringify(encrypted));
    });
    return Promise.all(encryptedShares);
  };

  /**
   * Given the number of shares at least above threshold, returns the secret
   * @param shares
   */
  recoverSecret = (shares) => {
    const sharesBuffer = shares.map(str => Buffer.from(str.slice(2), 'hex'));
    const resultBuffer = combine(sharesBuffer);
    return resultBuffer.toString();
  };

  /**
   * Given an encrypted share, decrypts it
   * @param encryptedShare
   * @param privateKey
   */
  decryptShare = async (encryptedShare, privateKey) => {
    const encryptedObject = cipher.parse(encryptedShare.slice(2));
    const decrypted = await decryptWithPrivateKey(
      privateKey.slice(2),
      encryptedObject,
    );
    return decrypted;
  };

  /**
   * Generates a stealth address, with related ephemeralPubkey
   * @param metaStealthPublicKey
   */
  generateStealthAddress = (metaStealthPublicKey) => {
    const ephemeralPrivateKey = generatePrivateKey();
    const ephemeral = privateKeyToAccount(ephemeralPrivateKey);
    // compute the shared secret using private key ephemeral * smart account viewing public key
    const sharedSecret = getSharedSecret(
      ephemeralPrivateKey.slice(2),
      metaStealthPublicKey.slice(2),
      false,
    );
    const hashedSharedSecret = keccak256(toHex(sharedSecret.slice(1)));
    const R_pubkey_spend = ProjectivePoint.fromHex(metaStealthPublicKey.slice(2));
    const stealthPublicKey = R_pubkey_spend.multiply(BigInt(hashedSharedSecret));
    const stealthAddress = '0x'+keccak256( Buffer.from(stealthPublicKey.toHex(), 'hex').slice(1)).slice(-40);
    return {
      address: stealthAddress,
      publicKey: '0x'+stealthPublicKey.toHex(),
      ephemeralPubKey: ephemeral.publicKey,
    };
  };

  /**
   * Get the stealth address from a retrieved ephemeral Public key
   * @param metaStealthPrivateKey
   * @param ephemeralPubKey
   */
  getStealthAddressFromEphemeral = (metaStealthPrivateKey, ephemeralPubKey) => {
    const metaStealth = privateKeyToAccount(metaStealthPrivateKey);
    const sharedSecret = getSharedSecret(
      metaStealthPrivateKey.slice(2),
      ephemeralPubKey.slice(2),
      false,
    );
    const hashedSharedSecret = keccak256(toHex(sharedSecret.slice(1)));
    const R_pubkey_spend = ProjectivePoint.fromHex(metaStealth.publicKey.slice(2));
    const stealthPublicKey = R_pubkey_spend.multiply(BigInt(hashedSharedSecret));
    return '0x'+keccak256( Buffer.from(stealthPublicKey.toHex(), 'hex').slice(1)).slice(-40);
  };

  /**
   * Given a private key and entropy, generates the private key of the setalth address
   * @param metaStealthPrivateKey
   * @param ephemeralPubKey
   */
  generateStealthPrivateKey = (metaStealthPrivateKey, ephemeralPubKey) => {
    const sharedSecret = getSharedSecret(
      metaStealthPrivateKey.replace('0x', ''),
      ephemeralPubKey.replace('0x', ''),
      false,
    );
    
    const hashedSharedSecret = keccak256(Buffer.from(sharedSecret.slice(1)));
    
    const privateKeyBigInt = (BigInt(metaStealthPrivateKey) * BigInt(hashedSharedSecret)) % CURVE.n;
    return pad(toHex(privateKeyBigInt));
  };
}
