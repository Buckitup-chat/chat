<template>
  <div class="flex flex-col max-w-3xl mx-auto p-6">
    <h1 class="text-2xl font-bold mb-6">Storage API Client 3</h1>
    
    <!-- Key Generation Section -->
    <div class="bg-white shadow-md rounded-lg p-6 mb-6">
      <h2 class="text-xl font-semibold mb-4">Key Pair</h2>
      <div class="mb-4">
        <button @click="generateKeyPair" class="bg-blue-500 hover:bg-blue-600 text-white font-medium py-2 px-4 rounded">
          Generate Key Pair
        </button>
      </div>
      <div v-if="publicKeyHex" class="grid grid-cols-1 md:grid-cols-2 gap-4">
        <div>
          <label class="block text-sm font-medium mb-1">Public Key (hex):</label>
          <textarea v-model="publicKeyHex" readonly class="w-full h-16 p-2 border border-gray-300 rounded font-mono text-xs"></textarea>
        </div>
        <div>
          <label class="block text-sm font-medium mb-1">Private Key (hex):</label>
          <textarea v-model="privateKeyHex" readonly class="w-full h-16 p-2 border border-gray-300 rounded font-mono text-xs"></textarea>
        </div>
      </div>
    </div>
    
    <!-- Operations Section -->
    <div class="bg-white shadow-md rounded-lg p-6 mb-6">
      <h2 class="text-xl font-semibold mb-4">Data Operations</h2>
      
      <!-- Store Data -->
      <div class="mb-6">
        <h3 class="text-lg font-medium mb-3">Store Data</h3>
        <div class="mb-3">
          <label class="block text-sm font-medium mb-1">Key:</label>
          <div class="flex items-center gap-2">
            <input 
              v-model="keyPrefix" 
              placeholder="Key prefix" 
              class="flex-1 p-2 border border-gray-300 rounded" 
            />
            <button @click="generateKeyId" class="bg-gray-300 hover:bg-gray-400 px-2 py-2 rounded">
              Generate ID
            </button>
          </div>
          <div class="mt-1 text-xs text-gray-600">
            Format: ["{{ keyPrefix || 'prefix' }}", {{ keyId || 'number' }}]
          </div>
        </div>
        <div class="mb-3">
          <label class="block text-sm font-medium mb-1">Value (JSON):</label>
          <textarea 
            v-model="payloadValueText" 
            class="w-full h-24 p-2 border border-gray-300 rounded font-mono text-sm"
            placeholder='{"message": "store this securely!", "timestamp": "2025-06-05T20:44:43Z"}'
          ></textarea>
        </div>
        <button @click="storeData" :disabled="!publicKeyHex" 
                class="bg-green-500 hover:bg-green-600 text-white font-medium py-2 px-4 rounded disabled:opacity-50 disabled:cursor-not-allowed">
          Store Data
        </button>
        <div v-if="storeResult" class="mt-2 p-2 rounded" :class="storeResult.success ? 'bg-green-100 text-green-700' : 'bg-red-100 text-red-700'">
          {{ storeResult.message }}
        </div>
      </div>
      
      <!-- Retrieve Data -->
      <div>
        <h3 class="text-lg font-medium mb-3">Retrieve Data</h3>
        <button @click="retrieveData" :disabled="!publicKeyHex" 
                class="bg-blue-500 hover:bg-blue-600 text-white font-medium py-2 px-4 rounded disabled:opacity-50 disabled:cursor-not-allowed mb-3">
          Retrieve All Data
        </button>
        <div v-if="retrievedData.length" class="p-3 bg-gray-100 rounded-lg overflow-auto max-h-96">
          <div v-for="(item, index) in retrievedData" :key="index" class="mb-3 p-2 bg-white rounded shadow">
            <div class="mb-1 font-semibold text-sm">Key: <pre class="inline">{{ JSON.stringify(item.key) }}</pre></div>
            <div class="pl-3">
              <pre class="whitespace-pre-wrap text-xs">{{ JSON.stringify(item.value, null, 2) }}</pre>
            </div>
          </div>
        </div>
        <div v-else-if="retrievedError" class="mt-2 p-2 bg-red-100 text-red-700 rounded text-sm">
          {{ retrievedError }}
        </div>
        <div v-else-if="retrieveAttempted" class="mt-2 p-2 bg-yellow-100 text-yellow-700 rounded text-sm">
          No data found.
        </div>
      </div>
    </div>
    
    <!-- Logs Section -->
    <div class="bg-white shadow-md rounded-lg p-6">
      <h2 class="text-xl font-semibold mb-2 flex justify-between items-center">
        <span>Operation Logs</span>
        <button @click="clearLogs" class="text-xs text-gray-500 hover:text-gray-700">Clear</button>
      </h2>
      <div class="bg-gray-100 p-3 rounded-lg h-48 overflow-y-auto font-mono text-xs">
        <div v-for="(log, index) in logs" :key="index" class="mb-1" :class="getLogClass(log.type)">
          [{{ log.timestamp }}] {{ log.message }}
        </div>
        <div v-if="!logs.length" class="text-gray-500 italic">No logs yet</div>
      </div>
    </div>
  </div>
</template>

<script>
import axios from 'axios';
import { generateKeypair, convertPrivateKeyToHex, base64ToArray, arrayToBase64, signDigest } from '@/libs/enigma.js';

export default {
  name: 'StorageApiClient',
  data() {
    return {
      // Key pair
      publicKeyBin: null,
      privateKey: null,
      publicKeyHex: '',
      privateKeyHex: '',
      
      // Token
      tokenKey: '',
      token: '',
      signature: '',
      
      // Payload
      keyPrefix: 'data',
      keyId: null,
      payloadValueText: JSON.stringify({
        message: "store this securely!",
        timestamp: new Date().toISOString()
      }, null, 2),
      
      // Results
      storeResult: null,
      retrievedData: [],
      retrievedError: null,
      retrieveAttempted: false,
      
      // Logs
      logs: []
    };
  },
  computed: {
    payloadKey() {
      return [this.keyPrefix, this.keyId];
    },
    payloadValue() {
      try {
        return JSON.parse(this.payloadValueText);
      } catch (e) {
        return null;
      }
    }
  },
  methods: {
    // Logging methods
    addLog(message, type = 'info') {
      const timestamp = new Date().toLocaleTimeString();
      this.logs.unshift({ message, type, timestamp });
    },
    
    clearLogs() {
      this.logs = [];
    },
    
    getLogClass(type) {
      switch(type) {
        case 'error': return 'text-red-600';
        case 'success': return 'text-green-600';
        case 'warning': return 'text-yellow-600';
        default: return 'text-gray-700';
      }
    },
    
    // Key pair generation
    async generateKeyPair() {
      try {
        this.addLog('Generating new key pair...');
        
        // Generate a new key pair using the Enigma library
        const { privateKey, publicKey } = generateKeypair();
        
        this.privateKey = privateKey;
        this.publicKeyBin = base64ToArray(publicKey);
        
        // Convert to hex for display
        this.privateKeyHex = convertPrivateKeyToHex(privateKey);
        this.publicKeyHex = await this.bytesToHex(this.publicKeyBin);
        
        // Reset other state
        this.tokenKey = '';
        this.token = '';
        this.signature = '';
        this.storeResult = null;
        this.retrievedData = [];
        this.retrievedError = null;
        this.retrieveAttempted = false;
        
        this.addLog('Key pair generated successfully', 'success');
      } catch (error) {
        console.error('Error generating key pair:', error);
        this.addLog(`Error generating key pair: ${error.message}`, 'error');
      }
    },
    
    generateKeyId() {
      this.keyId = Date.now();
      this.addLog(`Generated key ID: ${this.keyId}`);
    },
    
    // Token management methods
    async requestToken() {
      try {
        this.addLog('Requesting confirmation token...');
        
        // Request a new confirmation token from the API
        const response = await axios.get('/storage-api/confirmation-token');
        
        // Store the token key and token
        this.tokenKey = response.data.token_key;
        this.token = response.data.token; // This is base64 encoded
        
        this.addLog(`Token received: ${this.tokenKey.substring(0, 8)}...`, 'success');
        
        // Automatically sign the token
        await this.signToken();
        
        return true;
      } catch (error) {
        console.error('Error requesting token:', error);
        this.addLog(`Error requesting token: ${error.response?.data?.error || error.message}`, 'error');
        return false;
      }
    },
    
    async signToken() {
      try {
        if (!this.privateKey || !this.token) {
          throw new Error('No private key or token available');
        }
        
        this.addLog('Signing token...');
        
        // Sign the token using the private key
        // We need to convert the token back to base64 for signDigest
        const signatureBase64 = await signDigest(this.token, this.privateKey);
        
        // Convert the signature from base64 to hex for display and API calls
        const signatureArray = base64ToArray(signatureBase64);
        this.signature = await this.bytesToHex(signatureArray);
        
        this.addLog('Token signed successfully', 'success');
        return true;
      } catch (error) {
        console.error('Error signing token:', error);
        this.addLog(`Error signing token: ${error.message}`, 'error');
        return false;
      }
    },
    
    // Always get a fresh token before operations
    async ensureValidToken() {
      if (!this.publicKeyHex) {
        this.addLog('No key pair available. Please generate keys first.', 'warning');
        return false;
      }
      
      // Always request a new token for each operation
      // Since confirmation tokens can only be used once
      return await this.requestToken();
    },
    
    // Data operations/
    async storeData() {
      try {
        // Make sure we have a valid key ID
        if (this.keyId === null) {
          this.generateKeyId();
        }
        
        // Validate payload value
        if (!this.payloadValue) {
          throw new Error('Please provide valid JSON for the payload value');
        }
        
        // Get a fresh token for this specific operation
        this.addLog('Getting a new token for storage operation');
        if (!await this.ensureValidToken()) {
          return;
        }
        
        // Store token info temporarily for this operation
        const operationTokenKey = this.tokenKey;
        const operationSignature = this.signature;
        
        this.addLog(`Storing data with key: ${JSON.stringify(this.payloadKey)}...`);
        
        // Prepare the payload according to the backend API format
        const payload = {
          key: JSON.stringify(this.payloadKey),
          value: this.payloadValue
        };
        
        // Build the URL with query parameters
        const url = `/storage-api/put?pub_key=${this.publicKeyHex}&token_key=${operationTokenKey}&signature=${operationSignature}`;
        
        // Send the request with proper headers
        const response = await axios.post(url, payload, {
          headers: {
            'Content-Type': 'application/json'
          }
        });
        
        // Clear token after use
        this.tokenKey = '';
        this.token = '';
        this.signature = '';
        
        this.storeResult = {
          success: true,
          message: 'Data stored successfully!'
        };
        
        this.addLog('Data stored successfully', 'success');
        this.addLog('Token consumed', 'info');
      } catch (error) {
        console.error('Error storing data:', error);
        this.storeResult = {
          success: false,
          message: 'Error: ' + (error.response?.data?.error || error.message)
        };
        this.addLog(`Storage error: ${error.response?.data?.error || error.message}`, 'error');
        
        // Clear token on error too
        this.tokenKey = '';
        this.token = '';
        this.signature = '';
      }
    },
    
    async retrieveData() {
      try {
        // Get a fresh token for this specific operation
        this.addLog('Getting a new token for retrieve operation');
        if (!await this.ensureValidToken()) {
          return;
        }
        
        // Store token info temporarily for this operation
        const operationTokenKey = this.tokenKey;
        const operationSignature = this.signature;
        
        this.addLog('Retrieving all data...');
        
        // Build the URL with query parameters
        const url = `/storage-api/dump?pub_key=${this.publicKeyHex}&token_key=${operationTokenKey}&signature=${operationSignature}`;
        
        // Send the request with proper headers
        const response = await axios.get(url, {
          headers: {
            'Accept': 'application/json'
          }
        });
        
        // Clear token after use
        this.tokenKey = '';
        this.token = '';
        this.signature = '';
        
        // Store the retrieved data
        this.retrievedData = response.data;
        this.retrievedError = null;
        this.retrieveAttempted = true;
        
        this.addLog(`Retrieved ${this.retrievedData.length} items`, 'success');
        this.addLog('Token consumed', 'info');
      } catch (error) {
        console.error('Error retrieving data:', error);
        this.retrievedData = [];
        this.retrievedError = 'Error: ' + (error.response?.data?.error || error.message);
        this.retrieveAttempted = true;
        this.addLog(`Retrieval error: ${error.response?.data?.error || error.message}`, 'error');
        
        // Clear token on error too
        this.tokenKey = '';
        this.token = '';
        this.signature = '';
      }
    },
    
    // Helper methods for encoding/decoding
    async bytesToHex(bytes) {
      return Array.from(new Uint8Array(bytes))
        .map(b => b.toString(16).padStart(2, '0'))
        .join('');
    },
    
    base64ToArrayBuffer(base64) {
      const binaryString = atob(base64);
      const bytes = new Uint8Array(binaryString.length);
      for (let i = 0; i < binaryString.length; i++) {
        bytes[i] = binaryString.charCodeAt(i);
      }
      return bytes;
    }
  }
};
</script>