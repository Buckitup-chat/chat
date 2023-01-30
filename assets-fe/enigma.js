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


    let context = blf.key(key);
    let plaintext = 'Same with CFB. Full blocks only!';
    let ciphertext = blf.cfb(context, iv, Buffer.from(plaintext, 'utf8'));
    let decrypted = blf.cfb(context, iv, ciphertext, true);
  },
  encrypt: "todo",
  decrypt: "todo"

};

window.enigma = Enigma;
window.buffer = Buffer;
