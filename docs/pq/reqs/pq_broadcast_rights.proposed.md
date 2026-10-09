# PQ broadcast rights

**Area:** rights model (vouch tokens / access gating), plus admin-room UI
**Answers:** `pq_node_playback.proposed.md` §7 and §12.3
**Blocks:** playback, if the stub stays as §7 writes it — see below.

## Why

Node playback turns a Raspberry Pi into an output device: a user takes the
booth and the node decrypts their media to AUX/HDMI. Two questions follow, and
the playback spec deliberately refuses to answer either.

1. **Who may take the booth.** Being a party to a dialog says nothing about
   being allowed to play it aloud in this house.
2. **Who may evict the current broadcaster.** A lease has a 60 s TTL, so nobody
   holds the room by walking away — but a client that keeps heartbeating holds
   it indefinitely, and only its holder can release it. `:force_release` is the
   answer to that, and it needs an owner.

The hook this work implements, the stub it replaces, and the
`Chat.Admin.MediaSettings` naming constraint are specified in §7 of the
playback spec. Read them there — restating them here is how the two drift.

## The right belongs in the vouch forest, not in a store of its own

`pq_vouch_tokens.proposed.md` already defines scoped, revocable grants keyed on
`user_hash`: a `device.<sn>.<facility>` forest, prefix attenuation, signed
tombstones, graph traversal from the owner, and a max chain depth the owner
tunes (`pq_access_gating.proposed.md`). Broadcast rights belong on it rather
than in a second rights model with its own table, its own revocation rule and
its own audit.

That also settles the identity question this work cannot skip. Playback
authenticates ML-DSA and names people by `user_hash` (§6 hands the booth over
as `to_user_hash`), while the admin room stores `%Chat.Card{}` keyed by
secp256k1 `pub_key` (`AdminRoom.visit/1`) — nothing bridges the two. A grant
keyed on `user_hash` needs no bridge; an admin-DB store of cards would have to
build one first.

Three things about that forest this work has to decide rather than inherit:

- **Where `force_release` hangs.** Not as a sibling of the broadcast right:
  attenuation is prefix containment and wider scope wins, so a grant of
  `device.<sn>.playback` would silently confer eviction on every broadcaster.
  The operator power wants the `admin` facility, or an explicit rule that
  grants above the leaf are refused.
- **Whether the grant may be re-vouched.** The graph is transitive up to the
  owner's max depth, so at the default a broadcaster can extend the right two
  hops further. §7's default is restrictive by design; depth 1 for this
  facility, or a stated reason to allow more.
- **`playback` is a new first-level facility**, and the vouch spec keeps the
  core vocabulary compiled, with unknown scopes treated as deny until merged.
  Adding it is a vocabulary change plus a migration for peers that sync a
  grant they cannot yet read — not a row in an existing table.

## Scope

- Implement `Chat.Playback.Policy` against those scopes. If the vouch work has
  not landed yet, say so here and pick the smallest thing that migrates into
  it — not a parallel rights model.
- **Authenticate an operator over HTTP.** `:force_release` is an admin action,
  and admin-ness is decidable today only inside a LiveView socket
  (`main_live/page/lobby.ex` challenge-signs against the admin identity).
  Playback's API (§6) is not a LiveView.
- **Give the right a re-authorisation point.** `authorize/2` is consulted when
  the booth is taken and never again: a revoked grant keeps playing until the
  DJ releases or their heartbeat stops, and the one remedy — `:force_release` —
  is denied to everyone by default. The heartbeat (§2, every 20 s) is the
  natural place to ask again, and handover (`held → held`) is the other: the
  booth changes hands there without the rights model seeing the transfer, and
  §6 takes the recipient as a `to_user_hash` parameter. The `authorize/2` arity
  is closed; the action set is not.
- **Decide the granularity** — per-user, per-dialog, or both, and record the
  decision in this file. Per-room is not on the menu: the PQ data model has
  dialogs and not rooms (a playback item carries `dialog_hash`), and
  `rooms.<hash>` is marked future in the vouch forest.
- **Take the audit as a second hook.** `authorize/2` cannot produce it: it runs
  before the fact, never learns the outcome (an authorised claim that loses the
  race is not a claim), and is not called at all when a lease expires — which
  is the ordinary way the booth frees up. Ask playback for a
  `record(event, context)` on every booth transition, expiry included, and
  consume it here. The sink has to be durable, queryable by subject, and off
  the unauthenticated debug routes: `Chat.AdminDb.AdminLogger` is none of the
  three — it is a Logger backend pruned on every boot to the last three
  generations (`application.ex`), and served to anyone on the LAN at
  `GET /db_log` (`router.ex`, `:browser` pipeline, no auth plug).
- **Admin UI** for granting and revoking, in the admin room, alongside the
  existing removable-drive settings. It needs a list of subjects to grant to,
  and the admin room has no view of PQ users — the missing bridge above is the
  granting screen's problem too, not only the policy's.
- **Say whether a takeover is visible to the person cut off.** That is the half
  of §12.3 with no other owner.

## The stub as §7 writes it cannot be built

§7's fallback is "only devices explicitly paired with this node". There is no
pairing in this codebase — no registry, no flow, no key; the word appears in
the playback spec, one obsolete IPFS document, and nowhere in `lib/`. So either
the stub is defined against something that exists (the owner, plus whoever the
owner has vouched for), or it degrades to deny-all — and a deny-all stub means
this work blocks playback rather than following it. Decide that first.

## Not in scope

- The playback path itself — leases, queue, decryption, output.
- Any change to the `authorize/2` arity. If the rights model needs more
  context, extend the `context` map.
