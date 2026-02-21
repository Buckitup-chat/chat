# Electric API Sandbox - User Testing Interface

## Overview

Interactive web-based testing client for the Electric ingest API, providing visual testing and debugging capabilities for `user_card` and `user_storage` CRUD operations with Post-Quantum cryptographic authentication.

## Context

The Electric ingest API supports operations on `user_card` and `user_storage` tables using Proof-of-Possession challenge-response authentication. While command-line scripts (`scripts/post_electric_user.exs`, etc.) demonstrate API usage, developers need a visual interface to:

- Test API operations interactively
- Inspect full HTTP request/response cycles
- Understand Post-Quantum authentication flow
- Debug payload structures and encoding issues
- Learn API patterns through examples

## Requirements

### Route and Access

**REQ-1:** The sandbox SHALL be accessible at `/electric/user_sandbox`

**REQ-2:** A navigation card SHALL be added to the `/electric` landing page linking to the sandbox

### User Interface Layout

**REQ-3:** The interface SHALL provide three distinct areas:
- **Left Sidebar:** Collapsible documentation panel
- **Main Content:** Interactive API testing interface
- **Right Sidebar:** Request/response log viewer

### Documentation Sidebar (Left)

**REQ-4:** Documentation sidebar SHALL:
- Toggle visibility (show/hide)
- Display schema documentation for `user_card` and `user_storage`
- Support expandable/collapsible sections
- Show field names, types, and descriptions
- Provide example JSON payloads

**REQ-5:** Documentation SHALL include:
- `user_card` schema: user_hash, name, sign_pkey, contact_pkey, contact_cert, crypt_pkey, crypt_cert
- `user_storage` schema: user_hash, uuid, value
- Field type information (bytea, text, uuid)
- Encoding formats (e.g., `\x<hex>` for binaries)

### User Management (Main Content)

**REQ-6:** Initial State - When no user exists, SHALL display:
- Single "Create Test User" button centered in main area

**REQ-7:** User Creation SHALL:
- Generate Post-Quantum keypairs (ML-DSA-87 signing, ML-KEM-1024 encryption/contact)
- Compute user_hash as SHA3-512(sign_pkey) with 0x01 prefix
- Create user via Electric API challenge-response flow
- Display user information (name, truncated hash)
- Log all requests/responses

**REQ-8:** User Loaded State SHALL provide:
- Display of user name and hash (truncated to 12 hex chars)
- Form to update user name
- Button to delete user (with confirmation)
- Storage items section

**REQ-9:** User Operations SHALL support:
- **Update Name:** Change display name while preserving identity
- **Delete User:** Remove user and all associated storage items

### Storage Management

**REQ-10:** Storage Items Section SHALL:
- Display list of created storage entries (UUID + optional label)
- Show "No storage items" message when empty
- Provide actions for each item: view, edit, delete
- Include "Create Storage Item" button

**REQ-11:** Create Storage Item SHALL:
- Allow optional UUID specification (auto-generate if empty)
- Accept size parameter (1 byte to 10MB)
- Accept optional text label for identification
- Generate random binary data of specified size
- Store base64-encoded version for display
- Send binary as `\x<hex>` encoded JSON to API

**REQ-12:** View Storage Details SHALL:
- Display full UUID
- Show optional label
- Display size in human-readable format (bytes/KB/MB)
- Show complete base64-encoded value
- Provide scrollable view for large values

**REQ-13:** Edit Storage Item SHALL:
- Allow modification of size and label
- Regenerate new random binary data
- Preserve UUID
- Update entry via Electric API

**REQ-14:** Delete Storage Item SHALL:
- Prompt for confirmation
- Remove entry via Electric API
- Update local list immediately

### Request Logging (Right Sidebar)

**REQ-15:** Request Log SHALL:
- Display all API requests in reverse chronological order (newest first)
- Show both challenge and ingest requests for each operation
- Support scrolling through history
- Include "Clear Log" button

**REQ-16:** Each Log Entry SHALL display:
- HTTP method and URL path
- Response status code with color coding (green 2xx, red 4xx/5xx)
- Timestamp
- Collapsible sections for:
  - Request headers
  - Request body (pretty-printed JSON)
  - Response headers
  - Response body (pretty-printed JSON)

**REQ-17:** Status code color coding SHALL:
- Green background: 200-299 responses
- Red background: 400+ error responses
- Gray background: other status codes

### API Integration

**REQ-18:** All API operations SHALL use the Proof-of-Possession pattern:
1. Request challenge from `/electric/v1/challenge`
2. Sign challenge with ML-DSA-87 private key
3. Submit signed challenge with operation to `/electric/v1/ingest`

**REQ-19:** API operations SHALL include:
- **User Operations:** create, update name, delete
- **Storage Operations:** create (insert), update, delete

**REQ-20:** Request logging SHALL capture:
- Complete request headers (including content-type, authorization)
- Full request body with proper encoding
- Complete response headers
- Full response body
- Exact timestamp of each request

**REQ-21:** Binary data encoding SHALL:
- Store random binary data internally
- Display as base64 in UI
- Encode as `\x<hex>` format in JSON payloads sent to API
- Match encoding used in reference scripts

### Error Handling

**REQ-22:** Failed API operations SHALL:
- Still log the request/response
- Display error message to user
- Maintain application state (don't reset on error)
- Show error details in response body

**REQ-23:** UI Confirmations SHALL:
- Prompt before deleting user
- Prompt before deleting storage item
- Use browser native confirm dialog

### Data Persistence

**REQ-24:** Application state SHALL be:
- Maintained in LiveView assigns (ephemeral)
- Reset on page refresh (no backend persistence)
- Cleared when user is deleted

**REQ-25:** User identity SHALL:
- Generate new keypairs each time user is created
- Not persist across sessions
- Be fully contained in LiveView assigns

### User Experience

**REQ-26:** Loading states SHALL:
- Show visual feedback during API operations
- Disable action buttons during in-flight requests
- Re-enable after response received

**REQ-27:** Modals SHALL:
- Block background interaction
- Close on Cancel button
- Close on successful submission
- Dismiss with Close button (view details modal)

**REQ-28:** Form validation SHALL:
- Enforce size limits (1 byte - 10MB for storage)
- Accept valid UUID format or empty string
- Allow empty label (optional field)

## Implementation References

### Existing Code to Reuse

- `lib/chat/data/user.ex:79-112` - Post-Quantum key generation
- `scripts/post_electric_user.exs` - Challenge-response flow
- `scripts/update_electric_user_name.exs` - Update mutation patterns
- `scripts/create_electric_user_storage.exs` - Storage operations

### API Endpoints

- `POST /electric/v1/challenge` - Request authentication challenge
- `POST /electric/v1/ingest` - Submit mutations with signed challenge

### Authentication Format

```elixir
%{
  "auth" => %{
    "challenge_id" => "<uuid>",
    "signature" => "<base64-encoded ML-DSA-87 signature>"
  }
}
```

### Storage Value Encoding

- **UI Display:** Base64-encoded string
- **JSON Payload:** `\x<hex>` format (e.g., `\x54657374`)
- **Binary Size:** Maximum 10MB per entry

## Acceptance Criteria

**AC-1:** User can navigate to `/electric/user_sandbox` and see initial state

**AC-2:** User can create a test user and see it appear in main content area

**AC-3:** User can see challenge and ingest requests logged in right sidebar

**AC-4:** User can toggle documentation sidebar and expand/collapse sections

**AC-5:** User can update user name and see change reflected immediately

**AC-6:** User can create multiple storage items with different sizes

**AC-7:** User can view full details of any storage item

**AC-8:** User can edit storage item (size/label) and see it regenerate

**AC-9:** User can delete storage items and see them removed

**AC-10:** User can delete user and return to initial state

**AC-11:** All API operations log complete request/response data

**AC-12:** Request log persists across multiple operations

**AC-13:** Binary data is correctly encoded as `\x<hex>` in JSON payloads

**AC-14:** Failed requests still appear in log with error details

**AC-15:** Payload structure matches reference scripts exactly

## Testing Requirements

### Unit Tests

**TEST-1:** API client module SHALL have tests for:
- Successful create/update/delete operations
- Error handling and logging
- Challenge-response flow
- Payload structure validation
- Binary encoding correctness

### LiveView Tests

**TEST-2:** LiveView tests SHALL verify:
- Initial render state
- User creation updates state
- Storage item CRUD operations
- Modal show/hide behavior
- Request log accumulation
- Documentation sidebar toggle
- Form validation

### Integration Tests

**TEST-3:** End-to-end flow tests SHALL verify:
- Complete user lifecycle (create → update → delete)
- Complete storage lifecycle (create → edit → view → delete)
- Request logging across multiple operations
- Proper cleanup when user is deleted

### Manual Verification

**TEST-4:** Manual testing SHALL confirm:
- UI renders correctly in browser
- All buttons/forms are functional
- Modals display properly
- Request logs are readable
- Documentation is helpful
- Performance is acceptable with large storage values (5-10MB)
- Payload structure matches scripts when compared side-by-side

## Non-Functional Requirements

**NFR-1:** Response Time - UI SHALL remain responsive during API calls

**NFR-2:** Accessibility - All interactive elements SHALL be keyboard accessible

**NFR-3:** Browser Support - SHALL work in modern browsers (Chrome, Firefox, Safari)

**NFR-4:** Mobile - SHALL be usable on tablet-sized screens (768px+)

**NFR-5:** Code Quality - SHALL pass `make check` (format, credo, sobelow, dialyzer)

**NFR-6:** Documentation - Code SHALL include module docs and function specs

**NFR-7:** Error Messages - SHALL provide clear, actionable error messages to users
