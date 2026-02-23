# Dialog File Upload Flow - NaiveAPI GraphQL

This document describes the complete flow for uploading and sending files through dialogs using the BuckitUp GraphQL API (NaiveAPI).

## Overview

The file upload and sending process consists of 5 main steps:

1. **User Creation** - Create sender and receiver identities
2. **Upload Key Generation** - Get an upload key for the file
3. **Chunk Upload** - Upload file data in chunks via REST
4. **File Message Sending** - Send the file as a message in the dialog
5. **File Retrieval** - Read the file from the dialog (optional)

## API Endpoints

- **GraphQL Endpoint**: `http://localhost:4444/naive_api`
- **GraphQL Console**: `http://localhost:4444/naive_api_console` (API documentation)
- **Chunk Upload Endpoint**: `PUT http://localhost:4444/upload_chunk/{upload_key}`

## Step-by-Step Flow

### Step 1: User Creation

Create two users using the `userSignUp` mutation. Users can either provide their own keypair or let the system generate one.

**Mutation:**
```graphql
mutation UserSignUp($name: String!, $keypair: InputKeyPair) {
  userSignUp(name: $name, keypair: $keypair) {
    name
    keys {
      publicKey
      privateKey
    }
  }
}
```

**Variables:**
```json
{
  "name": "Alice",
  "keypair": {
    "publicKey": "02a1b2c3...",  // 66 char hex string (33 bytes)
    "privateKey": "a1b2c3d4..."  // 64 char hex string (32 bytes)
  }
}
```

**Key Generation:**
```elixir
# Generate Ed25519 keypair
{public_key, private_key} = :crypto.generate_key(:eddsa, :ed25519)

# Serialize to hex strings
public_key_hex = Base.encode16(public_key, case: :lower)   # 66 chars
private_key_hex = Base.encode16(private_key, case: :lower) # 64 chars
```

**Response:**
```json
{
  "data": {
    "userSignUp": {
      "name": "Alice",
      "keys": {
        "publicKey": "02a1b2c3...",
        "privateKey": "a1b2c3d4..."
      }
    }
  }
}
```

**Repeat for the second user (Bob).**

### Step 2: Upload Key Generation

Create an upload key that identifies the file upload and its destination.

**Mutation:**
```graphql
mutation UploadKey(
  $myKeypair: InputKeyPair!,
  $destination: InputUploadDestination!,
  $entry: InputUploadEntry!
) {
  uploadKey(
    myKeypair: $myKeypair,
    destination: $destination,
    entry: $entry
  )
}
```

**Variables:**
```json
{
  "myKeypair": {
    "publicKey": "02a1b2c3...",  // Alice's public key
    "privateKey": "a1b2c3d4..."  // Alice's private key
  },
  "destination": {
    "type": "DIALOG",
    "keypair": {
      "publicKey": "03d4e5f6...",  // Bob's public key
      "privateKey": "a1b2c3d4..."  // Alice's private key
    }
  },
  "entry": {
    "clientName": "vacation.jpg",
    "clientType": "image/jpeg",
    "clientSize": 1048576,
    "clientRelativePath": "/Downloads/vacation.jpg",
    "clientLastModified": 1679466076
  }
}
```

**Field Descriptions:**
- `myKeypair`: The sender's keypair (Alice)
- `destination.type`: Either `"DIALOG"` or `"ROOM"`
- `destination.keypair`: Destination keypair (receiver's public key + sender's private key for dialogs)
- `entry.clientName`: Original filename
- `entry.clientType`: MIME type (e.g., `"image/jpeg"`, `"application/pdf"`)
- `entry.clientSize`: File size in bytes
- `entry.clientRelativePath`: Path on client system
- `entry.clientLastModified`: Unix timestamp of file modification

**Response:**
```json
{
  "data": {
    "uploadKey": "a1b2c3d4e5f6789..."  // 64 char hex string (32 bytes)
  }
}
```

**What Happens Server-Side:**
1. Generates a unique upload key from: `hash([sender_id, destination, path, name, type, size, modified])`
2. Creates encryption secret for the file chunks
3. Encrypts the secret with sender's identity
4. Stores upload metadata in `UploadIndex`
5. Generates per-chunk secrets via `ChunkedFilesMultisecret`
6. Returns the upload key

### Step 3: Chunk Upload

Upload the file data in chunks using REST PUT requests.

**Endpoint:** `PUT /upload_chunk/{upload_key}`

**Chunk Configuration:**
- Standard chunk size: **10 MB** (10,485,760 bytes)
- Last chunk can be smaller
- Chunks must be uploaded with proper `Content-Range` headers

**Request Example:**
```http
PUT /upload_chunk/a1b2c3d4e5f6789... HTTP/1.1
Host: localhost:4444
Content-Type: application/octet-stream
Content-Range: bytes 0-10485759/104857600
Content-Length: 10485760

[binary chunk data]
```

**Headers:**
- `Content-Type`: `application/octet-stream`
- `Content-Range`: Format is `bytes {start}-{end}/{total_size}`
  - Example: `bytes 0-10485759/104857600` (first 10MB chunk)
  - Example: `bytes 10485760-20971519/104857600` (second 10MB chunk)
  - Example: `bytes 20971520-21000000/21000001` (last chunk, smaller)
- `Content-Length`: Size of this specific chunk

**Response:**
- `200 OK` - Chunk uploaded successfully
- `503 Service Unavailable` - Server busy, retry later

**Elixir Example:**
```elixir
file_path
|> File.stream!([], 10_485_760)  # 10MB chunks
|> Stream.with_index()
|> Enum.each(fn {chunk, index} ->
  offset = index * 10_485_760
  chunk_size = byte_size(chunk)
  range_end = offset + chunk_size - 1
  total_size = File.stat!(file_path).size

  Req.put!("http://localhost:4444/upload_chunk/#{upload_key}",
    body: chunk,
    headers: [
      {"content-type", "application/octet-stream"},
      {"content-range", "bytes #{offset}-#{range_end}/#{total_size}"},
      {"content-length", "#{chunk_size}"}
    ]
  )
end)
```

**What Happens Server-Side:**
1. Extracts upload key from URL
2. Reads chunk data from request body
3. Parses `Content-Range` header
4. Retrieves chunk-specific encryption secret via `ChunkedFilesMultisecret`
5. Encrypts chunk with Enigma cipher
6. Stores encrypted chunk: `Db[{:file_chunk, key, start, end}] = encrypted_chunk`
7. Marks chunk as stored

### Step 4: Send File Message

After all chunks are uploaded, send the file as a message in the dialog.

**Mutation:**
```graphql
mutation ChatSendFile(
  $peerPublicKey: PublicKey!,
  $myKeypair: InputKeyPair!,
  $uploadKey: FileKey!
) {
  chatSendFile(
    peerPublicKey: $peerPublicKey,
    myKeypair: $myKeypair,
    uploadKey: $uploadKey
  ) {
    id
    index
  }
}
```

**Variables:**
```json
{
  "peerPublicKey": "03d4e5f6...",  // Bob's public key
  "myKeypair": {
    "publicKey": "02a1b2c3...",   // Alice's public key
    "privateKey": "a1b2c3d4..."   // Alice's private key
  },
  "uploadKey": "a1b2c3d4e5f6789..."  // From step 2
}
```

**Response:**
```json
{
  "data": {
    "chatSendFile": {
      "id": "550e8400-e29b-41d4-a716-446655440000",  // Message UUID
      "index": 1  // Message index in dialog
    }
  }
}
```

**What Happens Server-Side:**
1. Looks up upload via `UploadIndex.get(upload_key)`
2. Validates upload exists (returns error if not found)
3. Decrypts file secret: `ChunkedFiles.decrypt_secret(upload.encrypted_secret, sender)`
4. Creates `Messages.File` struct with metadata
5. Finds or creates dialog between sender and receiver
6. Saves file secrets for both dialog participants:
   - `FileIndex.save(upload_key, alice_key, msg_id, secret)`
   - `FileIndex.save(upload_key, bob_key, msg_id, secret)`
7. Adds message to dialog
8. Returns message reference

### Step 5: File Retrieval (Reading Messages)

Read messages from the dialog, including file messages.

**Query:**
```graphql
query ChatRead(
  $peerPublicKey: PublicKey!,
  $myKeypair: InputKeyPair!,
  $before: Int,
  $amount: Int
) {
  chatRead(
    peerPublicKey: $peerPublicKey,
    myKeypair: $myKeypair,
    before: $before,
    amount: $amount
  ) {
    id
    index
    timestamp
    author {
      name
      publicKey
    }
    content {
      ... on TextContent {
        text
      }
      ... on FileContent {
        url
        type
        sizeBytes
        initialName
      }
      ... on RoomInviteContent {
        keys {
          publicKey
          privateKey
        }
      }
    }
  }
}
```

**Variables:**
```json
{
  "peerPublicKey": "03d4e5f6...",  // Bob's public key
  "myKeypair": {
    "publicKey": "02a1b2c3...",   // Alice's public key
    "privateKey": "a1b2c3d4..."   // Alice's private key
  },
  "before": null,   // Optional: read before this index
  "amount": null    // Optional: number of indexes (default 20)
}
```

**Response:**
```json
{
  "data": {
    "chatRead": [
      {
        "id": "550e8400-e29b-41d4-a716-446655440000",
        "index": 1,
        "timestamp": 1679466076,
        "author": {
          "name": "Alice",
          "publicKey": "02a1b2c3..."
        },
        "content": {
          "url": "/get/file/550e8400-e29b-41d4-a716-446655440000",
          "type": "IMAGE",
          "sizeBytes": 1048576,
          "initialName": "vacation.jpg"
        }
      }
    ]
  }
}
```

**File Download:**
```http
GET /get/file/550e8400-e29b-41d4-a716-446655440000 HTTP/1.1
Host: localhost:4444

# Returns decrypted file bytes
```

## Data Structures

### Key Formats

| Type | Binary Size | Hex String Length | Example |
|------|-------------|-------------------|---------|
| Private Key | 32 bytes | 64 chars | `a1b2c3d4e5f6...` |
| Public Key | 33 bytes | 66 chars | `02a1b2c3d4e5...` |
| Upload Key / File Key | 32 bytes | 64 chars | `f1e2d3c4b5a6...` |

**Serialization:**
```elixir
# Binary → Hex String
Base.encode16(binary, case: :lower)

# Hex String → Binary
Base.decode16!(hex_string, case: :lower)
```

### Upload Metadata

**Upload Struct:**
```elixir
%Upload{
  encrypted_secret: <<...>>,  # Encrypted chunk encryption key
  timestamp: 1679466076,      # Unix timestamp
  client_size: 1048576,       # File size in bytes
  client_type: "image/jpeg",  # MIME type
  client_name: "vacation.jpg" # Original filename
}
```

**File Message Data Array:**
```elixir
[
  upload_key,           # 32-byte binary
  secret_base64,        # Base64-encoded encryption secret
  size,                 # File size in bytes
  mime_type,            # "image/jpeg"
  filename,             # "vacation.jpg"
  formatted_size        # "1.00 MB" (human-readable)
]
```

## Storage

**Upload Index:**
```elixir
UploadIndex[upload_key] = %Upload{...}
```

**Encrypted Chunks:**
```elixir
Db[{:file_chunk, upload_key, start_byte, end_byte}] = encrypted_chunk_bytes
```

**File Secrets (per participant):**
```elixir
FileIndex[{participant_hash, upload_key, message_id}] = decrypted_secret
```

**Chunk Markers:**
```elixir
Db[{:chunk_key, {upload_key, start_byte, end_byte}}] = true
```

## Security Model

### Encryption Flow

1. **Upload Key Generation**:
   - Server generates initial encryption secret
   - Secret is encrypted with sender's identity
   - Per-chunk secrets derived via `ChunkedFilesMultisecret`

2. **Chunk Encryption**:
   - Each chunk encrypted with its own secret
   - Uses Enigma cipher algorithm
   - Chunks stored encrypted in database

3. **Secret Distribution**:
   - File secret saved separately for each dialog participant
   - Indexed by participant's dialog key
   - Enables both users to decrypt chunks

4. **File Retrieval**:
   - Reader's identity used to look up file secret
   - Secret used to decrypt chunks
   - Chunks assembled into original file

### Dialog Key Derivation

For dialog between Alice and Bob:
- `dialog.a_key` = `max(alice_pub_key, bob_pub_key)`
- `dialog.b_key` = `min(alice_pub_key, bob_pub_key)`
- Ensures consistent dialog identification regardless of who initiates

## Implementation Example

See [scripts/send_file_demo.exs](../scripts/send_file_demo.exs) for a complete working example.

**Run:**
```bash
# Start the server
cd chat && make iex

# In another terminal, run the script
elixir scripts/send_file_demo.exs
```

## Reference Implementation

### Test Files
- [test/naive_api/chat_test.exs](../test/naive_api/chat_test.exs) - Dialog file upload tests
- [test/naive_api/room_test.exs](../test/naive_api/room_test.exs) - Room file upload tests
- [test/chat_web/controllers/upload_chunk_controller_test.exs](../test/chat_web/controllers/upload_chunk_controller_test.exs) - Chunk upload tests

### Source Files
- [lib/naive_api/schema.ex](../lib/naive_api/schema.ex) - GraphQL schema
- [lib/naive_api/user.ex](../lib/naive_api/user.ex) - User signup
- [lib/naive_api/upload.ex](../lib/naive_api/upload.ex) - Upload key creation
- [lib/naive_api/chat.ex](../lib/naive_api/chat.ex) - Chat/dialog file sending
- [lib/chat_web/controllers/upload_chunk_controller.ex](../lib/chat_web/controllers/upload_chunk_controller.ex) - Chunk upload endpoint

## Error Handling

### Common Errors

**Wrong upload key:**
```json
{
  "errors": [
    {
      "message": "Wrong upload key",
      "path": ["chatSendFile"]
    }
  ]
}
```

**Invalid keypair format:**
```json
{
  "errors": [
    {
      "message": "Argument \"myKeypair\" has invalid value...",
      "path": ["chatSendFile"]
    }
  ]
}
```

**Upload timeout:**
- Uploads expire after a certain period
- Must complete chunk upload and send message before expiration

**Chunk upload failure:**
- HTTP 503: Server busy, retry later
- HTTP 400: Invalid Content-Range header
- HTTP 404: Upload key not found or expired

## Room File Upload

The flow is identical for rooms, with these changes:

**Mutation:** `roomSendFile` instead of `chatSendFile`

**Destination Type:** `"ROOM"` instead of `"DIALOG"`

**Destination Keypair:** Room's own keypair
```json
{
  "destination": {
    "type": "ROOM",
    "keypair": {
      "publicKey": "04a1b2c3...",  // Room's public key
      "privateKey": "b1c2d3e4..."  // Room's private key
    }
  }
}
```

**Query:** Use `roomRead` instead of `chatRead`

## Notes

- Dialogs are automatically created when first message is sent
- File chunks can be uploaded in any order
- All chunks must be uploaded before sending the file message
- Chunk size is configurable but defaults to 10 MB
- File encryption/decryption is fully handled server-side
- Clients only need to handle chunking and GraphQL requests
- The same upload key cannot be reused for multiple files
