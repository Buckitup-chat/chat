# Node Playback — the Booth

> Status: **proposed**. Covers three repositories: `platform` (firmware),
> `chat` (node application), `chat-frontend` (the phone, acting as the remote).

## Goal

A BuckitUp node plays media that lives in a chat out of its own audio jack and
HDMI port. The phone stays the interface: the user opens a media message and
sends it to the node, then controls playback from the phone.

A user should be able to:

- play an audio file, a video file, or a slideshow of images from a dialog on
  the node;
- build a playlist on the phone and hand it to the node;
- see who is currently broadcasting, and request the booth when it is busy;
- take the booth, run it, and leave it deliberately.

A node should:

- serve exactly one broadcaster at a time;
- never hold a decryption key longer than the item it is playing;
- keep chat sync working while it plays.

No browser runs on the node. Playback is a media pipeline (GStreamer or mpv)
supervised by the existing Elixir application through MuonTrap.

## Scope and non-goals

In scope: the booth session model, the waiting queue, the playback queue and
playlists, transport control, slideshow, key handling, the node API, and the
client UI.

Out of scope, tracked elsewhere:

- **Who is allowed to broadcast.** The rights model is admin-infrastructure
  work and is specified separately; this document defines the hooks it plugs
  into and nothing more.
- Firmware packaging (player binary, codecs, ALSA/DRM wiring) — a `platform`
  task; see the implementation plan.
- Multi-room or synchronised playback across nodes.
- Transcoding. The node plays what it can decode natively; anything else is
  reported as unsupported.

## 1. Security decision: session keys on the node

`pq_files.done.md §2` states the current guarantee plainly: chunks are
AES-256-GCM with a unique `enc_secret` per file, and *"the device stores and
serves the raw encrypted bytes and never sees plaintext"*. The `enc_secret`
lives inside the end-to-end encrypted message envelope, so the node does not
have it and cannot play a chat file on its own.

This feature requires a **named, bounded exception** to that guarantee: the
client hands the node a content key for the duration of playback.

Rules, all of them binding:

1. A key is scoped to **one session** and never reused across sessions. How
   much of the session it covers is the mode's business, not this rule's:
   attended holds one item at a time, unattended holds the queue (below).
2. The key hygiene of [pq_video_streaming §8.1](files/pq_video_streaming.done.md)
   applies unchanged — never logged, never in a URL, never in an error payload.
   What is new here is that the key arrives over the wire rather than being
   derived locally, so it lives in process memory only and is never written to
   disk.
3. No key outlives its item under any termination, normal or abnormal. Stating
   it as a property rather than as a callback is deliberate: `terminate/2` does
   not run on a brutal kill, so the guarantee has to come from the structure
   (an owning process per item, wiped by its supervisor) rather than from a
   single cleanup hook.
4. Decrypted bytes are never written to disk. They exist in RAM and in the pipe
   feeding the player, and nowhere else.
5. Keys are accepted **only over a confidential channel**, which for this
   purpose means exactly: TLS with a deployed certificate (`config/prod.exs`),
   a loopback request, or a key sealed to the node's own public key at the
   application layer (§12.1 — unresolved, and until it is, LAN deployments
   without a certificate do not get this feature). Anything else — plain HTTP
   over a LAN, a self-signed certificate the client did not pin — is refused
   with `insecure_channel`. The feature fails closed.
6. Landing this exception in [pq_files §2](files/pq_files.done.md), whose
   "the device never sees plaintext" is the sentence being amended, is a
   **precondition** of shipping the feature — not a promise this document
   makes on its own behalf. A guarantee that still reads as absolute where
   people look it up has not actually been amended.

### Attended and unattended playback

Two modes, chosen by the user, because they trade privacy against convenience:

| Mode | Keys the node receives | If the phone leaves |
|---|---|---|
| **Attended** (default) | one item at a time, fetched as it starts | playback stops at the end of the current item |
| **Unattended** | the session queue, up front | the queue plays to the end |

Attended is the default and is what the UI offers first. Unattended is an
explicit choice with explicit wording — the user is told the node will hold the
keys for the whole playlist.

Attended is only real if the transport makes it real: an item is queued
**without** its key, and the node asks for the key when the item starts
(§6). Shipping key-with-item would mean the node holds every queued key the
moment the playlist lands, which is unattended mode wearing the other name.

Whether unattended should exist at all is **§12.2, still open** — it is
specified here so the trade is visible, and everything it touches (this
table, the `draining` booth state, its acceptance criterion) comes out
together if the answer is no.

## 2. The booth

The node has one pair of speakers and one screen, so it has exactly one
broadcast session, called the booth. The user holding it is the DJ.

| State | Meaning |
|---|---|
| `free` | nobody is broadcasting |
| `held` | a DJ holds a live lease |
| `draining` | the lease is gone, unattended playback is finishing the current item |

Transitions:

- `free → held` — a claim from an authorised client.
- `held → free` — the DJ releases the booth, or the lease expires in attended
  mode, or an operator forces a release.
- `held → draining` — the lease expires in unattended mode.
- `draining → free` — the current item ends, or anyone claims the booth. A
  claim during `draining` wins: someone present in the room outranks a
  playlist whose owner has left. The waiting queue is not promoted while the
  booth drains — promotion happens on `free`, so nobody is handed a booth
  that is still making noise.
- `held → held` — handover to a named user who is waiting.

### Leases

The booth is held by a **lease**, not by a connection:

- TTL **60 s**, refreshed by a heartbeat every **20 s**;
- an expired lease frees the booth — a DJ who walks away with their phone,
  runs out of battery, or leaves the network cannot hold a room's speakers
  hostage;
- release is immediate and explicit ("leave the booth"), and does not wait for
  the TTL.

### The waiting queue

When the booth is busy, a claim joins a FIFO queue:

- each waiting client sees its position;
- leaving the queue is always available;
- when the booth frees, the head of the queue is promoted to `on_deck` and has
  **30 s** to confirm; on timeout it is skipped, not silently dropped, and the
  client is told why;
- the DJ may hand the booth directly to a named waiting user, which bypasses
  the FIFO order deliberately and visibly.

Booth and queue state is **ephemeral**: it lives in a GenServer, not in the
database. A node reboot frees the booth. This is the desired behaviour — a
physical resource should not stay locked by a record that outlived the room.

## 3. The playback queue

An item is a reference to media that already exists in a dialog, not a copy of
it:

| Field | Meaning |
|---|---|
| `dialog_hash`, `message_id`, `sign_hash` | the message the media came from |
| `part_index` | which content part of a composed message |
| `kind` | `audio` \| `video` \| `image` — derived, not a registry key: the envelope key plus `mime_type`, so audio is a `file` envelope with an `audio/*` type |
| `source` | `chunked` (file_id, key fetched per §6) or `inline` (bytes pushed by the client) |
| `title` | display string, supplied by the client |

The queue belongs to the session and dies with it. Playlists are a **client**
concept: they are built on the phone and stored in `user_storage`, which is
already end-to-end encrypted and synced; taking the booth pushes the chosen
playlist into the session queue. The node never stores a playlist.

## 4. Media sources and decryption

**Chunked content** (`file`, `image`, `video` envelopes): the bytes are already
on the node in `ChunkStore`, encrypted. The producer reads chunks, decrypts
each with the session key per the chunk format defined in
[pq_files §2](files/pq_files.done.md), and feeds a bounded read-ahead of 2–3
chunks (8–12 MB) into the player. The GCM tag is the integrity check;
`data_hash` on the chunk row is the second one already used by sync.

**Inline content** (`inline_image`, `inline_file`): these carry no per-file key
— the bytes sit inside the message envelope, encrypted with the dialog key the
node will never have. For these the client pushes the decrypted bytes directly.
They are bounded by the content spec (500 KB soft, 1 MB hard), so this is cheap
and needs no streaming.

**Incomplete files.** The node may not hold every chunk yet; the
`missing_chunks` queue already tracks that. The item then reports `syncing`
with a percentage and the queue moves on or waits, as configured — it never
looks like a hang.

**Seeking** is at chunk granularity (4 MB): the producer restarts at the chunk
containing the target offset and the player resyncs. Adequate for audio and for
coarse video scrubbing; finer seeking is not offered rather than faked.

## 5. Slideshow

A slideshow is an ordered list of image items with:

- a dwell interval (default 7 s, configurable per session);
- manual advance from the phone (next / previous), which resets the interval;
- a fit policy (contain, by default — no cropping of someone's photo);
- optional loop.

The phone acts as a presentation remote: it shows the current image, its
position in the deck, and the next/previous controls. Background audio under a
slideshow is **not** in this version; it is a second queue and a second set of
transport semantics, and it can wait for evidence that anyone wants it.

## 6. Node API

All endpoints live under `/playback`. Every request is signed by the client's
ML-DSA key and replay-protected with the existing one-time challenge broker
(60 s TTL). Authorisation is delegated (§7).

| Method | Path | Body | Result |
|---|---|---|---|
| GET | `/playback/booth` | — | state, DJ display name, now playing, queue length, your position |
| POST | `/playback/booth/claim` | mode (attended/unattended) | `{held, lease}` or `{queued, position}` |
| POST | `/playback/booth/heartbeat` | lease | refreshed lease, or `expired` |
| POST | `/playback/booth/release` | lease | `free`, or the promoted successor |
| POST | `/playback/booth/handover` | lease, `to_user_hash` | `held` by the named user |
| POST | `/playback/booth/confirm` | — | claims an `on_deck` promotion |
| DELETE | `/playback/booth/queue` | — | leaves the waiting queue |
| POST | `/playback/booth/force_release` | reason | operator action, capability-gated (§7) |
| POST | `/playback/items` | item, no key (inline bytes for inline content) | queued item id |
| POST | `/playback/items/:id/key` | session key for that item | accepted / `insecure_channel` |
| PATCH | `/playback/items/:id` | position | reordered |
| DELETE | `/playback/items/:id` | — | removed |
| POST | `/playback/transport` | `play` \| `pause` \| `next` \| `prev` \| `seek` \| `stop` | new state |
| POST | `/playback/output` | `sink: jack \| hdmi`, `volume` | new output state |
| GET | `/playback/status` | — | item, position, state, sync progress, pushed as they change |

The paths above are illustrative; what is contractual is the set of operations
and the reason codes. The push mechanism for `/playback/status` (SSE, a
Phoenix channel, long-poll) is deliberately unnamed here — it is the one
transport choice that shapes the client, and it should be decided with §12.1
rather than inherited from a table.

Every rejection carries a machine-readable reason (`booth_busy`,
`lease_expired`, `not_authorised`, `file_syncing`, `unsupported_format`,
`insecure_channel`). A refusal is never a silent no-op.

## 7. Authorisation hooks (delegated)

This document does not define who may broadcast. It defines two predicates the
rights model must provide:

```elixir
Chat.Playback.Policy.authorize(action, context) :: :ok | {:error, reason}
```

`action` is `:claim_booth`, `:queue_item`, `:force_release`; `context` carries
the user, the node, and — for `:queue_item` — the dialog and item the key
would unlock. One deliberately loose signature, because the rights work has
to be free to decide its own granularity: a pair of `may_broadcast?(user)`
booleans would quietly foreclose per-dialog rights, and per-dialog is the
sharper question here, since claiming the booth is also asking the node to
decrypt somebody's media.

Until the admin-infrastructure work lands, the policy module ships a
conservative stub: only devices explicitly paired with this node may claim the
booth or queue items, and `:force_release` is denied to everyone. Playing
sound in someone's room is a physical act, so the default is restrictive by
design.

Naming note: `Chat.Admin.MediaSettings` already means **removable drives**
(backup / cargo / onliners). Playback must not reuse "media" in admin naming;
this feature namespaces as `Chat.Playback.*`.

## 8. Client UI

**Discovery.** The node advertises a playback capability. Every control below
appears only when a capable node is reachable; otherwise the chat looks exactly
as it does today.

**From a message.** A media message (audio, video, image) gains:

- `Play on <node name>` — claims the booth if free, else offers to queue;
- `Add to node queue` — enabled while you are the DJ, with a reason shown when
  it is not.

**Booth indicator.** A compact chip, visible wherever playback is relevant:

- `Booth free`,
- `On air: Alice` with what is playing,
- `You're #2 in line` with a cancel action,
- `You're on air` for the DJ, with a live indicator that cannot be missed.

**DJ panel** (bottom sheet):

- now playing with progress and remaining time;
- transport: play/pause, previous/next, seek, stop;
- output: jack or HDMI, and volume;
- the session queue with reorder and remove;
- attended/unattended switch, with plain wording about what unattended means;
- **Leave the booth** — always available, always one tap.

**Taking the booth from the queue.** When promoted, the phone shows a prompt
with a 30 s countdown: `You're on air — confirm`. Ignoring it passes the turn
to the next person, and says so.

**Playlists.** Built on the phone from messages across dialogs, stored in
`user_storage`, named, reorderable. `Send to node` pushes a playlist into the
session queue. A playlist holds references, never copies, so deleting the
original message removes the item.

**Slideshow.** Multi-select images in a dialog → `Slideshow on node`, with the
interval and loop choice, then the remote view with previous/next and the deck
position.

**Errors are shown as themselves.** `File is still syncing (42%)`,
`Format not supported by this node`, `Booth taken by Alice`,
`This node has no secure channel — playback disabled`. Never a spinner that
means an error.

## 9. Node-side output

- **HDMI**: a now-playing card (title and DJ name) for audio, full-screen video
  for video, full-screen images for slideshow, and `Booth free` when idle.
- **Audio-only deployments** need no screen; nothing in the design depends on
  one being attached.

## 10. Invariants

- At most one booth holder at any moment. No playback happens without a holder,
  except a `draining` unattended item finishing.
- A session key is never persisted, never logged, and never outlives its item.
- Decrypted media bytes never touch disk.
- Keys are refused over a non-confidential channel; the feature fails closed.
- Booth state is ephemeral; a reboot frees the booth.
- Playback never starves chat sync or chunk upload; both keep working while the
  node plays.
- Every refusal is explicit and carries a reason.

## 11. Acceptance criteria

1. Audio to the jack and video to HDMI, driven end to end from the phone.
2. Two clients claim the booth: one becomes DJ, the other queues, sees its
   position, and is promoted on release.
3. The DJ's phone goes offline (airplane mode): attended playback stops, the
   booth frees within the lease TTL, the next in line is promoted.
4. Handover and `leave the booth` behave exactly as specified, including the
   30 s confirmation timeout.
5. Unattended: the DJ's phone goes offline mid-item, the booth enters
   `draining`, the current item finishes, and the booth frees — and a claim
   arriving during `draining` cuts the item short and takes the booth
   immediately, with the waiting queue untouched until the booth is free.
5. Playing a file that is still syncing reports progress and never hangs.
6. Seeking across chunk boundaries works; a corrupted chunk fails loudly and
   quickly, with no noise on the speaker.
7. Keys: none in logs, none on disk, wiped on stop, crash, and lease expiry —
   verified by inspecting process state and the filesystem after each case.
8. A node without a confidential channel refuses playback with
   `insecure_channel`.
9. Playback for two hours with chat sync running: no drift, no leak, ingest
   latency unchanged within the recorded baseline.
10. Slideshow: interval advance, manual advance, loop, and a mixed deck of
    inline and chunked images.

## 12. Open questions

1. **Key transport without TLS.** Does the node have a published keypair a
   client can encrypt to (the way user cards work), so the key can be sealed at
   the application layer on a LAN with no certificate? If not, LAN-only
   deployments lose this feature until they have one.
2. **Is unattended mode allowed at all?** It hands a node the keys for a whole
   playlist. Convenient for a party, and a larger dent in §1. Product call.
3. **Force-release policy** — who is an operator, and is a takeover visible to
   the person being cut off? Answered by the rights work.
4. **Slideshow with background audio** — deferred; revisit on demand.
5. **Queue etiquette** — should a DJ have a maximum hold time when others are
   waiting, or is social pressure enough?

## 13. Related work

- `pq_files.done.md` — chunk storage, encryption, and the guarantee §1 amends.
- `pq_video_streaming.done.md` — the existing chunk-wise streaming design on
  the web client, mirrored here for the node pipeline.
- `07_content_polymorphism.md` — the content envelopes items refer to.
- Implementation plan and phasing, including the firmware work: kept with the
  project brief rather than in this document.
