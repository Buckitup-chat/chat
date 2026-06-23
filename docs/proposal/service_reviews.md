# Service Reviews Proposal

## Goal

Add a review system for service entities (businesses, venues, etc.) with post-quantum cryptographic guarantees matching the rest of the platform.

A user should be able to:

- discover services (coffee shops, venues, etc.)
- write a review with chosen visibility: to_public or to_service
- comment on any review they can see
- trust that visibility guarantees are cryptographic, not server-enforced

A service owner should be able to:

- register a service with its own PQ identity
- choose a moderation mode for public reviews (pre, post, or none)
- moderate public reviews (approve, reject, hide)
- receive private feedback (to_service reviews)

## Three entities

```
Service (the coffee shop)
│  own PQ identity, owned by a user
│
├── Review (by any user)
│   ├── to_public   — cleartext + signed, moderated by owner
│   ├── to_contacts — (deferred, see Future section)
│   └── to_service  — encrypted for service owner only
│
└── Comment (by anyone who can see the parent review)
    └── encrypted with same key as parent review
```

## Service

A service is a first-class entity with its own PQ identity. It is not a room, though it shares crypto patterns with rooms (keypair, owner, discoverability).

A service has:

- its own ML-DSA-87 signing keypair
- its own ML-KEM-1024 encryption keypair
- an owner (the user who created it)
- a moderation policy for public reviews
- public metadata (name, description — signed by owner)

The service identity is separate from the owner's personal identity. One user can own multiple services.

### Why not a room

Rooms are conversation spaces. Services are entities people review. They share crypto infrastructure but have different semantics:

- rooms have members who chat; services have reviewers who evaluate
- room membership is about participation; service visibility is about trust tiers
- rooms don't need moderation workflows; services do
- the review/comment hierarchy doesn't map to room message threading

Keeping them separate avoids overloading the room model and allows independent evolution.

## Review visibility tiers

### to_public

Content stored in cleartext. Signed by the author with ML-DSA-87 for non-repudiation. Anyone can read and verify authorship.

Subject to owner moderation (pre or post, depending on service config).

### to_service

Content encrypted via ML-KEM-1024 to the service's `crypt_pkey`. Only the service owner can decapsulate and decrypt.

Private feedback — not visible to anyone else. Not subject to moderation.

## Comments

Comments inherit the parent review's visibility envelope.

### On a public review

Cleartext + ML-DSA-87 signed by commenter. Anyone can read.

### On a to_service review

Two-party exchange between the review author and the service owner. Each encrypts to the other's `crypt_pkey` via ML-KEM-1024. Effectively a dialog scoped to this review.

## Moderation (public reviews only)

The service owner chooses a moderation mode per service.

### No moderation

Public reviews go live immediately. No owner action needed.

### Pre-moderation

1. Author submits review with `moderation_status: pending`
2. Content is KEM-encrypted to the service owner (temporarily to_service)
3. Author also provides a publication envelope: the cleartext content + author ML-DSA-87 signature, wrapped under the service's `crypt_pkey`
4. Owner decapsulates, reads, decides:
   - **Approve**: owner publishes the signed cleartext into `published_content_b64`, signs the approval with own ML-DSA-87 key. Result is dual-signed: author proves authorship, owner proves approval
   - **Reject**: owner writes a signed rejection. Content stays encrypted. Only owner and author (locally) have it
5. Before approval only the owner sees content. After approval everyone sees author-signed cleartext + owner-signed approval

### Post-moderation

1. Review goes public immediately (cleartext + author signature)
2. Owner can write a signed hide action (`moderation_status: hidden`)
3. Hidden reviews are filtered from the public feed but still exist cryptographically
4. Owner can unhide (signed action)

All moderation actions are ML-DSA-87 signed by the owner — clear audit trail.

## Data model

### service

```
service
├── service_hash          — SHA3-512 of service identity
├── owner_hash            — user_hash of the owner
├── sign_pkey             — ML-DSA-87 public key
├── crypt_pkey            — ML-KEM-1024 public key
├── name_b64              — service name (signed)
├── moderation_mode       — :pre / :post / :none
├── sign_b64              — owner's ML-DSA-87 signature over all fields
└── owner_timestamp       — causal ordering
```

### review

```
review
├── review_hash           — SHA3-512 of content
├── service_hash          — which service
├── author_hash           — who wrote it
├── visibility            — :public / :service
├── content_b64           — encrypted or cleartext depending on visibility
├── published_content_b64 — cleartext after pre-moderation approval
├── sign_b64              — author's ML-DSA-87 signature
├── moderation_status     — :none / :pending / :approved / :rejected / :hidden
├── moderation_sign_b64   — owner's ML-DSA-87 signature on moderation action
├── owner_timestamp
└── parent_sign_hash      — for edits (version chain)
```

### comment

```
comment
├── comment_hash          — SHA3-512 of content
├── review_hash           — which review
├── author_hash           — who commented
├── content_b64           — encrypted with same key as parent review
├── sign_b64              — commenter's ML-DSA-87 signature
├── owner_timestamp
└── parent_comment_hash   — for threading (nil for top-level comments)
```

## Electric shapes

### service shape

Synced to everyone — public directory of services.

Access control: only the owner (authenticated via `sign_pkey`) can write or update.

### review shape

Synced by `service_hash` — client requests reviews for a specific service. Client decrypts what it can based on visibility and available keys.

Access control: author authenticated via `sign_pkey`. Owner can write moderation fields (`moderation_status`, `moderation_sign_b64`, `published_content_b64`).

### comment shape

Synced by `review_hash` — client requests comments for a specific review.

Access control: commenter authenticated via `sign_pkey`. For to_service reviews, only the review author and service owner can comment.

## Signature coverage

### Service

Owner signs: `service_hash || owner_hash || sign_pkey || crypt_pkey || name_b64 || moderation_mode || owner_timestamp`

### Review

Author signs: `review_hash || service_hash || author_hash || visibility || content_plaintext || owner_timestamp`

The signature covers plaintext content, not the encrypted blob. This allows:

- public reviews: signature verifiable by anyone against cleartext
- to_service: owner decrypts first, then verifies
- pre-moderation approval: owner publishes cleartext + original author signature, third parties can verify

### Moderation action

Owner signs: `review_hash || moderation_status || owner_timestamp`

### Comment

Commenter signs: `comment_hash || review_hash || author_hash || content_plaintext || owner_timestamp`

## Security properties

### Non-repudiation

All reviews and comments are ML-DSA-87 signed. Authors cannot deny having written a review. Owners cannot deny having approved or hidden one.

### Visibility guarantees

Cryptographic, not server-enforced. The server stores ciphertext and cannot read to_service content. Changing visibility tier requires re-encryption with different keys.

### Moderation transparency

All moderation actions are signed. Pre-moderation approval produces dual-signed content (author + owner). The history of moderation actions is auditable.

### Forward secrecy

Same as the rest of the system: none. Key compromise enables retroactive decryption. This is a known trade-off for deterministic multi-device sync.

## Open questions

### 1. Service discovery

How are services discovered? Options:

- global directory (all services listed, like public rooms)
- location-based discovery (requires geolocation metadata on services)
- search/category browsing
- shared via links

### 2. Service metadata

What metadata should a service carry beyond name? Address, hours, category, images — these are product decisions that don't affect the crypto architecture but need schema space.

### 3. Rating system

Should reviews include a structured rating (1-5 stars, thumbs up/down) separate from free-text content? If so, is the rating always public (aggregatable) or follows the review's visibility?

### 4. Comment threading

Flat comments (all top-level) or threaded (via `parent_comment_hash`)? Flat is simpler. Threading adds depth but complexity.

### 5. Review editing

The `parent_sign_hash` field supports edit chains (like dialog messages). Should edits be:

- visible as a chain (all versions readable)
- latest-only (old versions hidden but cryptographically preserved)
- disallowed (reviews are immutable once posted)

### 6. SaaS model

How does the SaaS aspect work? Possible angles:

- service creation requires a subscription
- moderation features are premium
- analytics/aggregation is the paid tier
- the review infrastructure itself is the product

## Future: to_contacts visibility

A third visibility tier where the review author's contacts can see the review. This is the author's property — controlled by the author's trust network (dialog partners), not the service owner's.

Crypto approach: author generates a symmetric `contacts_key`, wraps it for each dialog partner using existing dialog `sender_msg_key`. All contacts-only reviews use this key. Key rotates when contacts change.

This is a separate concern involving the broader contacts/trust model and will be designed independently.

## Implementation phases

### Phase 1 — Service entity

- `service` Ecto schema and migration
- `service` Electric shape with owner access control
- service creation UI (name, moderation mode)
- service directory / listing

### Phase 2 — Public reviews and comments

- `review` Ecto schema and migration
- `review` Electric shape
- public review submission and display
- ML-DSA-87 signing and verification
- `comment` schema and shape
- comment submission and display

### Phase 3 — To-service reviews and moderation

- to_service review encryption (KEM to service)
- pre-moderation flow (submit, approve/reject, publish)
- post-moderation flow (hide/unhide)
- moderation UI for service owners
- to_service comment encryption (two-party)

### Phase 4 — Contacts visibility (future)

- contacts key infrastructure
- contacts-only review encryption/decryption
- depends on broader contacts/trust model design
