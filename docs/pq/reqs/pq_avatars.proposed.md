# PQ Avatars

## Purpose

A user's profile photos — any number of them, the newest one shown as the
avatar and all of them browsable as a gallery — reach the people they talk to,
end-to-end encrypted, with nothing new on the server.

## Problem

Today an avatar never leaves its owner. It is stored in the owner's
`user_storage`, encrypted under a key from the owner's own `crypt_skey`, so no
one else can decrypt it, and `user_cards` has no avatar field. A contact sees a
generated placeholder.

Putting the photo in `user_cards` would make it public: cards are readable by
everyone who can read the shape, and a photo is the most identifying thing an
account can publish. Encrypting it to each contact separately would need a
per-pair channel — and that channel already exists: the dialog.

## Approach

**A photo travels as dialog content.** Two content types
([07 § `"avatar"`, `"avatar_removed"`](../invariants/07_content_polymorphism.md#avatar))
carry a photo and its withdrawal inside ordinary `dialog_messages` rows. The
server stores ciphertext and learns nothing — not even that a row is a photo,
only its size class. Integrity, ordering, edits and deletion are the dialog's
own.

**Each photo has an id.** `avatar_id` (16 random bytes, lowercase hex) names one
photo across every dialog and every message that carries it, so the same photo
sent to ten contacts, or sent again later, is one gallery entry, and a removal
names exactly what it removes.

### The gallery a reader sees

For one sender in one dialog, the reader walks the sender's live (not deleted)
messages in dialog order — by `message_id`, a UUIDv7 signed with the row — and
within a message, its parts in order:

- `avatar(id, photo)` puts `id` at the newest position with that photo, whether
  or not it was there before;
- `avatar_removed(id)` takes `id` out.

What is left, newest first, is the gallery; its newest entry is the **current
avatar**. Only the sender's own messages count: a photo of someone else is a
picture, not their avatar. A deleted message contributes nothing, so deleting
the row that carried a photo also removes it from that dialog. A message is read
at its current revision; the sender may edit their own photos.

Setting an older photo as the avatar again is sending `avatar` for its id: it
moves to the newest position, in Telegram's terms "set as main".

### Delivery

The owner's client sends, to every dialog the account has:

1. **On a change** — a photo added, removed or set as main — one message with
   the one `avatar` or `avatar_removed` part.
2. **On a new dialog** — the first time this account sends in a dialog that has
   no `avatar` part from it — one message with the whole gallery, oldest first,
   one `avatar` part per photo. Readers apply it like any other message, so it
   reproduces the gallery's order.

A client that was offline sends the same messages when it returns; the dialog's
outbox already keeps them durable. The optical handshake (PQ2) needs no
change: confirming a contact makes the dialog, and rule 2 sends the gallery
into it.

### The photo

`photo` is a nested image element, [`"inline_image"`](../invariants/07_content_polymorphism.md#inline_image)
or [`"image"`](../invariants/07_content_polymorphism.md#image):

- **The client resizes** before sending: at most 640 px on the longer side.
- **`"image"` (out-of-band chunks) is the norm.** The photo is uploaded once as
  a file and every dialog's message references the same `file_id` and key, so
  a gallery of ten sent to fifty contacts is fifty small messages, not five
  hundred copies, and a new-dialog message stays far below the 1 MB row limit.
  The thumbhash lets a reader draw the avatar before the chunks arrive.
- **`"inline_image"`** is accepted for a photo small enough to inline; a
  reader treats both the same.
- A reader verifies the file as for any image in that dialog
  ([pq_files](files/pq_files.done.md)): the uploader is the sender.

### The owner's own gallery

The owner's devices share one list of the account's photos — ids, photo
elements, order — in an ordinary `user_storage` slot reached through the root
map, **not** at a constant uuid, for the reason
[pq_recovery_shares § What the owner sees](pq_recovery_shares.proposed.md#what-the-owner-sees)
gives. Every device sends from it; it is the source of rule 2.

### What a reader keeps

A reader's client may cache each contact's current avatar — the decrypted
thumbnail and the photo reference — next to the contact in its own storage, so
the contact list does not have to read every dialog to draw its avatars. The
dialog stays the source of truth: the cache is rebuilt from it.

## Scope

In: one-to-one dialogs; photos. Out, for now: rooms (a room has no per-pair
channel; a room photo is a room's, not a member's); video avatars (the type is
a nested element, so `{"video": …}` can be allowed later without a new type);
a public avatar for people one has no dialog with.

## Invariants

- An avatar is never in `user_cards` or any other row readable beyond the
  dialog.
- A gallery is computed per dialog from that dialog's messages; no device
  merges galleries across dialogs.
- Only the sender's own messages make or change the sender's gallery.

## Open questions

- **Retention of avatar files.** A photo's chunks must outlive the messages
  that reference them for as long as the photo is in a gallery; the file GC
  ([pq_files § 8](files/pq_files.done.md)) does not know about references
  yet.
- **Withdrawing from a contact.** Removing a photo cannot unsend it: a reader
  who already downloaded it keeps the bytes.
