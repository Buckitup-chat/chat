const jsSHA3 = require("jssha/dist/sha3");
const blf = require('blowfish-js');
var Buffer = require('buffer/').Buffer  // note: the trailing slash is important!

const Enigma = {
  help: `All the functions inputs are Base64 encoded strings`,
  hash: function(b64_data) {
    const shaObj = new jsSHA3("SHA3-256", "B64");
    shaObj.update(b64_data);
    return shaObj.getHash("B64");
  },
  cipher: function(b64_plain_data, b64_password) {
    const pass_buffer = Buffer.from(b64_password, 'base64')
    pass = Buffer.from(new Uint8Array(pass_buffer.buffer, 8, 16))
    key1 = Buffer.from(new Uint8Array(pass_buffer.buffer, 0, 8))
    key2 = Buffer.from(new Uint8Array(pass_buffer.buffer, 24, 8))

    key = new Array(8)
    for (i = 0; i < 8; i += 1) {
      key[i] = key1[i] ^ key2[i]
    }

    let context = blf.key(Buffer.from(pass));
    let ciphered = blf.cfb(context, Buffer.from(key), Buffer.from(b64_plain_data, 'base64'));

    return ciphered
  },
  decipher: function(b64_ciphered_data, b64_password) {
    const pass_buffer = Buffer.from(b64_password, 'base64')
    pass = Buffer.from(new Uint8Array(pass_buffer.buffer, 8, 16))
    key1 = Buffer.from(new Uint8Array(pass_buffer.buffer, 0, 8))
    key2 = Buffer.from(new Uint8Array(pass_buffer.buffer, 24, 8))

    key = new Array(8)
    for (i = 0; i < 8; i += 1) {
      key[i] = key1[i] ^ key2[i]
    }

    let context = blf.key(Buffer.from(pass));
    let deciphered = blf.cfb(context, Buffer.from(key), Buffer.from(b64_ciphered_data, 'base64'), true);

    return deciphered
  },
  encrypt: "todo",
  decrypt: "todo",

  base64_to_string: function(b64_data) {
    return Buffer.from(b64_data, 'base64').toString();

  },
  base64_to_array: function(b64_data) {
    const buffer = Buffer.from(b64_data, 'base64');

    return new Uint8Array(buffer.buffer, buffer.byteOffset, buffer.byteLength);
  },
  array_to_base64: function(array) {
    return Buffer.from(array).toString('base64');
  },
  string_to_base64: function(string) {
    return Buffer.from(string).toString('base64');
  },
  shortcode_form_full_key: function(b64_full_key) {
    const buffer = Buffer.from(b64_full_key, 'base64')
    const public_key = Buffer.from(new Uint8Array(buffer.buffer, 32, 33)).toString('base64')
    const public_hash = this.hash(public_key)
    const hash_buffer = Buffer.from(public_hash, 'base64')
    const code = Buffer.from(new Uint8Array(hash_buffer.buffer, 0, 3))

    return code.toString('hex');
  }

};

window.enigma = Enigma;
window.Buffer = Buffer;
window.blf = blf;
