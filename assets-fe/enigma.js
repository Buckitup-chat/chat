const jsSHA3 = require("jssha/dist/sha3");
const blf = require('blowfish-js');
var Buffer = require('buffer/').Buffer  // note: the trailing slash is important!

const Enigma = {
  help: `All the functions work with Base64 encoded strings`,
  hash: function(b64_data) {
    const shaObj = new jsSHA3("SHA3-256", "B64");
    shaObj.update(b64_data);
    return shaObj.getHash("B64");
  },
  cipher: "todo",
  decipher: function(b64_ciphered_data, b64_password) {
    const pass_buffer = Buffer.from(b64_password, 'base64')
    pass = Buffer.from(new Uint8Array(pass_buffer.buffer, 8, 16))
    key1 = Buffer.from(new Uint8Array(pass_buffer.buffer, 0, 8))
    key2 = Buffer.from(new Uint8Array(pass_buffer.buffer, 24, 8))

    key = new Array(8)

    for (i = 0; i < 8; i += 1) {
      console.log(key1[i], key2[i], key1[i] ^ key2[i])
      key[i] = key1[i] ^ key2[i]
    }


    console.log(pass_buffer)
    console.log(key1, pass, key2)
    console.log(key)




    let context = blf.key(Buffer.from(key1));
    //let plaintext = 'Same with CFB. Full blocks only!';
    //let ciphertext = blf.cfb(context, iv, Buffer.from(plaintext, 'utf8'));
    let deciphered = blf.cfb(context, Buffer.from(key1), Buffer.from(b64_ciphered_data, 'base64'), true);

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
  }

};

window.enigma = Enigma;
window.Buffer = Buffer;
window.blf = blf;
