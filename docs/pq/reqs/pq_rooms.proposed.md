# PQ Rooms

Group conversations of up to a few hundred members, end-to-end encrypted,
on the same building blocks as two-person [dialogs](pq_dialogs.done.md):
- signed rows;
- ML-KEM-1024 key wrapping;
- causal ordering by `refs_map` ([04_ordering.md](../invariants/04_ordering.md));
- membership through [vouch tokens](pq_vouch_tokens.in_progress.md).

Status: proposed.

---

## Decisions

Taken by the owner, 2026-10-27.

| Question | Decision |
|---|---|
| History for a new member | A per-room switch: with it on, a new member reads the whole history; with it off, only what is written after they join |
| Room types | As in the legacy rooms (`lib/chat/rooms/room.ex`): **public**, **request**, **private** |
| Size | Up to hundreds of members. Larger audiences are broadcast channels, a separate topic |
| Read state | No per-message receipts. Read state comes from [checkpoints](../invariants/07_content_polymorphism.md#checkpoint) in a later phase, possibly as a per-member "read up to here" view |
| Membership | Visible to the server |

---

## Terms

| Term | Meaning |
|---|---|
| **Room identity** | A `user_cards` identity that is the room. `room_hash` is its `user_hash` |
| **Owner** | Holds the room identity's secret keys and acts as the room: admits, removes, rotates keys, edits settings. The creator; co-owners receive the keys by delegation |
| **Member** | Holds a vouch from the room and the room's key for the epochs they may read |
| **Epoch** | A period with one symmetric room key. A new epoch starts whenever someone must stop or must not start reading |

---

## The room is a subaccount

A room is an owned subaccount of its creator
([pq_subaccounts.proposed.md](pq_subaccounts.proposed.md)).

- Its keys live in the creator's keyring and reach every device the creator uses.
- Writing as the room uses the same per-identity session as notes to self ([pq_notes_to_self.proposed.md](pq_notes_to_self.proposed.md)) and venues.
- A co-owner is a delegate: they hold the full keys.
- Withdrawing a co-owner means a new room identity, as for venues. Revocable moderators are a later phase (see [Phases](#phases)).

The legacy rooms already worked this way. A room was an identity, and joining meant receiving it (`Room.approve_request/4` ciphers the room identity for the requester). Here only owners hold the room identity. Members get only the epoch keys, so removing a member is possible.

---

## Membership: vouches rooted at the room

A vouch token says "the issuer trusts the subject within this scope". The server checks a chain of vouches from the scope's **root** to the author of a write (`VouchToken.chain_distance(root, subject, scope, max_depth)`). Each tree of scopes has its own root:

| Scope | Root | Grants |
|---|---|---|
| `device.<sn>.storage.write` | The server's owner | Writing to this server ([pq_access_gating.done.md](pq_access_gating.done.md)) |
| `origins.<origin_hash>.reviews.write` | The venue | Writing reviews for this venue (reviews) |
| `rooms.<room_hash>.write` | The room identity | Writing to this room |

`rooms.*` is already reserved in the resource forest as future work. This requirement adds it to `VouchToken.resource_forest/0`.

**Rules:**
- **Who issues.** A member's vouch is issued **by the room identity**: chain distance 1, maximum depth 1. Members never vouch for others into a room. Removing a member is then one tombstone and breaks no one else's chain.
- **Two separate checks.** On a server in `guarded` or `trust` mode, writing to a room needs both chains: to the server's owner (server access) and to the room (room access).
- **Leaving and removal.**
  - Removing a member tombstones their room vouch and starts a new epoch without them.
  - A member who leaves publishes a leave intent (see `room_requests`). An owner's client then does the same.

---

## Keys: epochs

- **The epoch key** is 32 random bytes, made by an owner. Epoch numbers start at 1 and increase.
- **Delivery** is a `room_keys` row per member per epoch: ML-KEM-1024 to the member's `crypt_pkey`, then AES-256-GCM. This is the wrap of [pq_dialogs.done.md](pq_dialogs.done.md) § Key wrapping, salt `buckitup/room-wrap/v1`.
  - About 1.6 KB per member, so a few hundred members cost a few hundred KB per epoch.
  - Every device of a member unwraps it with the account's `crypt_skey`; nothing extra is needed per device.
- **A new epoch starts:**
  - when a member is removed or leaves;
  - when a member joins and the history switch is **off**: messages written in the current epoch before they joined must stay unreadable to them.
- **History switch on:** a new member also receives `room_keys` rows for every earlier epoch.
- **Per-author message key**, so authors do not share nonce space and reactions bind to an author:

  ```
  sender_room_key = HKDF-SHA3-256(epoch_key, salt = "buckitup/room-mk/v1", info = "room-mk" || sender_hash)
  ```

  The salt `buckitup/room-mk/v1` is the one [09_symmetric_keys.md](../invariants/09_symmetric_keys.md) reserves for rooms.
- **Authorship** never depends on the shared key. Every row is signed by its author's ML-DSA-87 key, as in dialogs.
- **A removed member keeps the keys of the epochs they had.** They can still read what they could read before, and nothing after.

---

## Tables

The tables mirror the dialog tables and the integrity triad of [02_integrity.md](../invariants/02_integrity.md).

| Table | Key | Signed by | Notes |
|---|---|---|---|
| `room_keys` | `(room_hash, epoch, member_hash)` | Room identity | `kem_wrap_key`, `wrapped_epoch_key`. `deleted_flag` is always false: a key once given cannot be taken back |
| `room_requests` | `(room_hash, requester_hash)` | Requester | `intent`: `join` or `leave`. Public and request rooms only |
| `room_messages` | `message_id` | Author | As `dialog_messages`, with `room_hash` and `epoch` in place of `dialog_hash` |
| `room_messages_versions` | `(message_id, sign_hash)` | Author | As `dialog_messages_versions` |
| `room_message_reactions` | as dialogs | Reactor | `reaction_hash` is a keyed MAC under the reactor's `sender_room_key` |

No receipts table (see Decisions).

**Server checks on ingest**, besides the signature and the integrity triad:
- **`room_messages`, `room_messages_versions`, `room_message_reactions`:** the author has `chain_distance(room_hash, author, "rooms.<room_hash>.write", 1)`, and the row's `epoch` has a `room_keys` row for that author.
- **`room_keys`:** signed by the room identity.
- **`room_requests`:** signed by the requester; refused for a private room.

**Shapes:** by `room_hash`. Members subscribe to their rooms' rows and to their own `room_keys` rows by `member_hash`.

**Ordering:** `refs_map` per `room_hash`, as [04_ordering.md](../invariants/04_ordering.md) foresees ("extends to rooms once `room_hash` lands").

---

## Settings

The room's settings live in the room identity's own User Storage, sealed under the current epoch key so that every member can read them:
- name, description, avatar;
- type;
- the history switch.

On each new epoch they are resealed.

**The card name** is public:
- **Public room:** its real name, so it can be found.
- **Request or private room:** a neutral name chosen as for derived identities (`DERIVED_CARD_NAMES` in `@buckitup/pq-client`). The real name stays in the sealed settings.

---

## Joining, by type

| Type | How one joins |
|---|---|
| **Private** | Only by an owner's invitation. The owner vouches and wraps the key(s). Requests are refused |
| **Request** | The person publishes a `join` request. An owner approves it by hand: vouch and wrap |
| **Public** | As request, but an owner's client approves automatically when it sees the request. Admission waits until one of the owners' devices is online |

The link to a room (QR or text) carries `room_hash`. A directory of public rooms is a later phase.

Legacy public rooms let any member approve. Here only owners admit, which keeps every member at chain distance 1 and removal clean. Moderators who admit are a later phase.

---

## What the server sees

**Sees:**
- every room's members (the vouches) and its size;
- who writes when, and message sizes;
- the epoch rotations;
- a public room's name.

**Does not see:**
- the content;
- the names and settings of request and private rooms;
- which message a reaction or edit belongs to beyond its `message_id`.

---

## Phases

| Phase | Scope |
|---|---|
| **1. Private rooms** | Room identity as an owned subaccount; invitation, removal, leave; epochs and the history switch; messages, edits, deletions, reactions; settings |
| **2. Request and public rooms** | `room_requests`, manual and automatic approval, room links |
| **3. Read state** | Checkpoints in rooms; "read up to here" per member |
| **4. Moderators and directory** | `rooms.<room_hash>.admin`: moderators admit and remove without the room's keys. They wrap epoch keys, and their `room_keys` rows are valid by an admin chain. A directory of public rooms |

**Depends on:**
- the per-identity session (notes to self, PR 1; subaccounts phase 1);
- the keyring of [pq_subaccounts.proposed.md](pq_subaccounts.proposed.md).

---

## Open questions

1. Rotate the epoch key on a schedule as well, for example monthly, or only on membership changes?
2. A member who leaves: should their own messages stay, as in dialogs, or offer to retract them?
3. Hard cap on members: enforce on the server (count of room vouches), or leave it to the client?
