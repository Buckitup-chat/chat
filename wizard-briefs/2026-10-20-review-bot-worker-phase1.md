---
task: "Design ReviewBotWorker GenServer and complete Phase 1 of review write tokens"
model: claude-opus-5-5
date: 2026-10-20
status: superseded-by-issue-726
---

## Goal
Add a per-origin `ReviewBotWorker` that holds the decrypted bot identity in memory and signs and ingests PQ rows in-process, plus the "Enable Review Invitations" flow that creates the bot, encrypts it, vouches it and activates it. Together these complete Phase 1 of `pq_review_write_tokens`.

## Approach

**Decryption: per-device activation.** The `origin_bots` row stays as the spec says: the bot identity encrypted to the origin, synced to every device, and the source of truth for whether the bot is live or tombstoned. A second wrap is added for each device:
- The owner's client already holds the origin `crypt_skey`, so it can open `origin_bots.encrypted_identity_b64`.
- It re-wraps the identity to the target device's `ServerIdentity.crypt_pkey` with `EnigmaPq.kem_encrypt/3`, salt `"buckitup/origin-bot-device/v1"`.
- It POSTs the result to a new activation endpoint, authenticated by the origin's proof of possession (PoP).
- The device stores the wrapped blob in `AdminDb` (CubDB, device-local, survives repo switches) and decrypts it with `ServerIdentity.get().crypt_skey`.

This fits resolved question #8 in the spec (each device must be allowed explicitly, with its own device vouches). The same UI step issues the device vouches and the device activation.

*Rejected:*
- Copying origin keys onto the device: the device would then hold the origin `sign_skey` and could rewrite the origin.
- A synced `origin_bot_devices` PQ table: other peers can't read it, it adds a migration, a shape and validation, and it gains nothing over AdminDb.
- Having the device "decrypt the origin_bots row" as the spec says: impossible, the device has no origin key.

**Supervision: top-level `Chat.ReviewBot.Supervisor` in `Chat.Application`, not a stage in the staged boot trees.**
- There are three staged trees: host `Chat.DbBootSupervisor`, device `Platform.App.DatabaseSupervisor`, and `Platform.App.Drive.MainDbSupervisor`. Adding the bots to them would either duplicate bots or restart them on every internal↔main repo switch.
- The bots don't depend on any one repo: `Chat.Pq.Ingest.apply/2` resolves `Chat.Db.repo()` on each call.
- Repo and Electric readiness are handled inside the Observer, the same way `ShapeConsumer` does it (`Chat.Db.repo_ready?()` plus backoff).

**Observing synced data:** an `Observer` GenServer that follows the `ShapeConsumer` pattern. It runs a monitored Task that streams the local embedded Electric `origin_bots` shape via `Phoenix.Sync.Client.stream/2`, sends `{:change, op, value}` / `:up_to_date` messages to itself, and restarts with backoff. This is what makes "start on sync" work: a device activated before its `origin_bots` row arrives from a peer starts the worker when the row lands. Point lookups (`User.get_card`, `OriginBot.get_origin_bot`) use Ecto, as validation already does. The "no direct DB in Electric" rule applies to sandbox LiveViews, not to server-side workers.

*Rejected:* polling (adds latency, and the spec asks for observation), and PubSub broadcast from ingest (it misses rows written by `NetworkSynchronization.Electric.ShapeWriter`).

**Ingest:** the worker calls `Chat.Pq.Ingest.apply(mutations, Ingest.self_pop(sign_skey))` directly. No HTTP. This is the path the `ingest.ex` moduledoc already anticipates.

## Steps

1. **Spec amendment** – `chat/docs/pq/reqs/reviews/pq_review_write_tokens.in_progress.md`
   - Rewrite "Device startup flow" (lines 83–89), Admin UI step 9 (line 321) and the "On other devices" paragraph (line 323) to describe device activation: the client re-wraps the identity to the device's `ServerIdentity.crypt_pkey`, and the device stores it in AdminDb.
   - Change the identity blob from `sign_skey <> crypt_skey` (lines 81 and 306) to versioned JSON: `{"v":1,"sign_skey":b64,"crypt_skey":b64,"contact_skey":b64}`. Raw concatenation depends on OTP's ML-DSA/ML-KEM private-key encoding lengths, and chat-frontend must produce the same bytes in JS.
   - Add the activation endpoint to the "API surface" table.
   - Why: the current text can't be implemented.

2. **Expose the device KEM key** – `chat/lib/chat_web/controllers/device_identity_controller.ex`, `sync_bot_identity/0`
   - Add `crypt_pkey` (base64) to the `sync_bot` map. The client should cross-check it against the sync bot's `user_cards.crypt_cert` (`EnigmaPq.verify(crypt_pkey, crypt_cert, sign_pkey)`).
   - Why: the client needs a public key to wrap the bot identity to.

3. **`Chat.ReviewBot.Identity`** – new file `chat/lib/chat/review_bot/identity.ex`, pure functions:
   - `@origin_salt "buckitup/origin-bot/v1"`, `@device_salt "buckitup/origin-bot-device/v1"`.
   - `encode(identity_map) :: binary` and `decode(binary) :: {:ok, %{sign_skey, crypt_skey, contact_skey}} | {:error, _}`. The JSON keeps only the secret keys (`v` = 1).
   - `wrap(identity, crypt_pkey, salt) :: {secret, encrypted}` and `unwrap(secret, encrypted, crypt_skey, salt) :: {:ok, identity} | {:error, _}`. `unwrap` must rescue or catch `aes_gcm_decrypt` / decapsulation failures.
   - `matches_card?(identity, %UserCard{})`:
     - Sign a random probe with `sign_skey` and verify it against `card.sign_pkey`.
     - KEM round-trip: `encapsulate_secret(card.crypt_pkey)` → `decapsulate_secret(_, crypt_skey)`. Extract the `decrypts_for?` logic from `electric_live/moderation_sandbox_live/identity.ex:91` into this module and reuse it there.
   - Why: one codec shared by the creation flow, activation and the worker, which keeps it consistent with the frontend's JS version.

4. **`Chat.ReviewBot.Creation`** – new file `chat/lib/chat/review_bot/creation.ex`, pure mutation builders. They're used by the sandbox and tests, and chat-frontend mirrors them in JS.
   - `new_bot(origin_name)` → `User.generate_pq_identity("ReviewBot_" <> origin_name)`; `card = User.extract_pq_card/1`.
   - `card_batch(card)` → user_cards insert mutation (`syncMetadata.relation "user_cards"`). PoP: bot.
   - `origin_batch(bot_card, bot_identity, origin_identity, origin_crypt_pkey)` → one batch, PoP: origin:
     - (a) an `origin_bots` insert. `secret_b64` / `encrypted_identity_b64` come from `Identity.wrap(.., origin_crypt_pkey, @origin_salt)`. Also set `deleted_flag: false` and `owner_timestamp: Chat.TimeKeeper.now_unix()`. Sign with the origin `sign_skey` over `Integrity.signature_payload/1`, and compute `sign_hash` the same way `origin_sandbox_live/api_client.ex:142 sign_origin/2` does.
     - (b) a `vouch_tokens` insert: `kind "origins.<origin_hash>.reviews.write"`, issuer = origin, subject = bot.
     - Both rows go in one batch because both checks need the same PoP (origin). One batch makes it atomic.
   - `device_vouch_batch(owner_identity, bot_hash, device_id)` → one vouch per shape: `device.<device_id>.storage.write.<shape>` for `:review`, `:review_password_candidate`, `:review_post_right_candidate`, `:review_revoke_right_candidate`. Take the names from `shape_name/0` of each shape module, not literals. PoP: device owner.
   - `activation_payload(bot_identity, bot_hash, origin_hash, server_crypt_pkey)` → `Identity.wrap(.., @device_salt)` plus the hashes.
   - Reuse case: if `OriginBot.list_live_for_origin(origin_hash)` is not empty, skip the card and origin batches. Decrypt the existing row with the origin `crypt_skey`, then only run the device vouches and activation for this device. This prevents bot fragmentation.
   - Why: in-process mutations take decoded binaries (see `test/chat/pq/ingest_test.exs`). Over HTTP, `IngestUtil.decode_mutation_fields` expects base64/hex suffixes, so the sandbox must encode.

5. **`Chat.ReviewBot.Activations`** – new file `chat/lib/chat/review_bot/activations.ex`. AdminDb persistence under key `:pq_review_bots` (a map `bot_hash => %{origin_hash, secret, encrypted}`), following `ServerIdentity` / `OwnerBootstrap`.
   - `put(bot_hash, entry)`, `delete(bot_hash)`, `all()`, `get(bot_hash)`.
   - `activate(%{bot_hash, origin_hash, secret, encrypted}, pop_context)`, as a `with` chain:
     - `{:origin_pop, ...}`: `EnigmaPq.verify(challenge, signature, User.get_card(origin_hash).sign_pkey)`.
     - `{:gate, WriteGate.check_access(origin_hash, :origin_bot)}`: reuses the device gate, so in enforced mode only vouched origins can place bots.
     - `{:decrypts, Identity.unwrap(.., ServerIdentity.get().crypt_skey, @device_salt)}`.
     - `{:card_matches, Identity.matches_card?(id, User.get_card(bot_hash))}`.
     - Then `put`, then `Phoenix.PubSub.broadcast(Chat.PubSub, "review_bots", {:activated, bot_hash})`.
   - Store only the wrapped form, never plaintext keys.
   - Why: decrypting at activation time catches bad blobs immediately, and the Observer re-decrypts on boot.

6. **Activation endpoint** – new file `chat/lib/chat_web/controllers/origin_bot_activation_controller.ex`, and `chat/lib/chat_web/router.ex` in the scope at line 244 next to `post "/ingest"`.
   - Add `post "/origin_bot_activation", OriginBotActivationController, :create`.
   - Params: `bot_hash`, `origin_hash`, `secret_b64`, `encrypted_identity_b64`, `auth`.
   - Use `IngestPop.context(params)` for the PoP, decode base64, call `Activations.activate/2`. Respond 200 / 403 / 422.
   - Add `delete` (same PoP) → `Activations.delete` plus broadcast `{:deactivated, bot_hash}`.
   - Why: chat-frontend and the sandbox both need an HTTP way in.

7. **`Chat.ReviewBot.Worker`** (the spec's "ReviewBotWorker"; put that name in the moduledoc) – new file `chat/lib/chat/review_bot/worker.ex`.
   - `use GenServer`, `use Toolbox.OriginLog`, `import Tools.GenServerHelpers`. `restart: :transient`.
   - `start_link(%{bot_hash, origin_hash, identity})`, registered as `{:via, Registry, {Chat.ReviewBot.Registry, bot_hash}}`.
   - State: `%{bot_hash, origin_hash, identity}`.
   - Public API, which must never return secret keys:
     - `whereis(bot_hash)`
     - `running?(bot_hash)`
     - `ingest(bot_hash, mutations)` → `call {:ingest, m}` → `Ingest.apply(m, Ingest.self_pop(identity.sign_skey))`; use a timeout above `@ingest_timeout`.
     - `sign(bot_hash, payload)` → ML-DSA signature, for Phase 2 token rows.
     - `info(bot_hash)` → `%{bot_hash, origin_hash}`.
   - `init` logs the start and broadcasts `{:review_bot, :started, bot_hash}` on `"review_bots"`.
   - **`@impl format_status/1`** must redact `identity` (replace it with `:redacted`).
   - Phase 2 hooks (token create/bind, capture, GC timer) attach here later. Don't add them now.

8. **`Chat.ReviewBot.Observer`** – new file `chat/lib/chat/review_bot/observer.ex`, modelled on `NetworkSynchronization.Electric.ShapeConsumer`. Keep it under 300 lines; extract a `stream.ex` helper if needed.
   - `init`: subscribe to `"review_bots"`, `{:continue, :start_stream}`.
   - Stream Task: `Phoenix.Sync.Client.stream(Chat.Data.Schemas.OriginBot, live: true, replica: :full, errors: :stream)`. Dispatch messages as `{:change, op, value}`, `:up_to_date` and `:must_refetch`. On `:DOWN`, use exponential backoff, and guard with `Chat.Db.repo_ready?()`. Don't persist offsets: the table is small, so always resync fully.
   - Reconcile rule, applied to each change, on `:up_to_date` and on `{:activated | :deactivated, hash}`:
     - A worker should run iff `Activations.get(bot_hash)` exists **and** the `origin_bots` row is live (`deleted_flag == false`) **and** `row.origin_hash == activation.origin_hash`.
     - Start: `Identity.unwrap` + `matches_card?`, then `DynamicSupervisor.start_child`.
     - Stop: `DynamicSupervisor.terminate_child`.
     - Keep `%{bot_hash => row_live?}` from the stream in state.
     - On an `origin_bots` tombstone, also call `Activations.delete(bot_hash)`.
   - Unwrap failures are logged without key material and the bot is skipped. The Observer must not crash.
   - Why: a single place makes the start/stop decision, so the same code handles boot, activation, sync arrival and revocation.

9. **`Chat.ReviewBot.Supervisor`** – new file `chat/lib/chat/review_bot/supervisor.ex`. `strategy: :rest_for_one`, children:
   - `{Registry, keys: :unique, name: Chat.ReviewBot.Registry}`
   - `{DynamicSupervisor, name: Chat.ReviewBot.WorkerSupervisor}`
   - `Chat.ReviewBot.Observer`

10. **Wire into the app** – `chat/lib/chat/application.ex`, `more_children/0` (around line 73, non-test only, like `ReviewCandidateCleaner`).
    - Append `Chat.ReviewBot.Supervisor`. It depends on PubSub, AdminDb, ServerIdentity and Challenge, which all start earlier in `Chat.Supervisor`'s list.
    - Platform needs no change: chat's application runs on the device too.

11. **Sandbox UI** – `origin_sandbox_live/render.ex` is already 295 lines, so:
    - Add a new component `chat/lib/chat_web/live/electric_live/origin_sandbox_live/review_bot.ex` (button, status) and a client `review_bot_client.ex` (HTTP ingest of the three batches with base64 encoding, then the activation POST). Pull `crypt_pkey` from `/device_identity` (step 2).
    - Hook the event into `index.ex`.
    - Show the bot status by reading the `origin_bots` shape plus a "running here" indicator (RPC/registry lookup is fine for dev).
    - Follow `electric_live/CLAUDE.md` conventions (request log, shortcodes).

12. **chat-frontend follow-up issue.** File a separate issue for the JS "Enable Review Invitations" flow, mirroring steps 3–4 and the activation POST. Toggling `origin_settings.review_access` to `invite_only` stays a separate control and is not flipped automatically.

13. **Update the spec checklist** (lines 372–374 and 388) as items land. Run `graphify update .` from the monorepo root only.

## Gotchas

- **Key leakage:** `GenServer` crash reports and `:sys.get_state` dump state, and `AdminLogger` persists logs. `format_status` redaction is required on the Worker, and the Observer must never put an unwrapped identity in its state or in log lines. Don't `inspect` unwrap errors that contain blobs.
- **PoP is per ingest call:** origin-signed rows (`origin_bots` + origin vouch) and owner-signed device vouches can't share a batch. The bot's `user_cards` row needs the bot's own PoP, and it must be ingested before `origin_bots` (`sync_required_parents` needs `{:user_card, bh}`).
- **Device owner ≠ origin owner:** device vouches must be issued by `OwnerBootstrap.owner()`. If the origin owner isn't the device owner, step 3 needs the device owner, so the UI must say so. In `:open` gate mode the vouches aren't enforced but should still be created.
- **Electric stack restarts:** `Chat.PhoenixSyncReinit.reinit/0` (repo switch, `chat/lib/chat/db.ex:149`, platform `phoenix_sync_init.ex:48`) kills the embedded stack, and the Observer's stream task dies with it. The backoff and full resync handle this. Workers keep running, but ingest calls fail while the repo is unavailable, so callers should expect `{:error, _}`, `DBConnection.ConnectionError` or `Postgrex.Error` (rescue them, as the controller does).
- **Phoenix.Sync 0.6.1 nil-resume bug** (`chat_web/live/phoenix_sync_patch.ex`): check whether `Client.stream` is affected. If so, call `Electric.Client.stream` with an explicit `Phoenix.Sync.Client.new!()` the way the patch does.
- **Test env:** the embedded Electric stack may not run in tests (`config/test.exs:31`). Design the Observer so tests can `send` it `{:change, ...}` / `:up_to_date` directly, and allow a `stream: false` start option.
- **`Chat.Data.VouchToken` uses `Chat.Repo` directly** rather than `repo()`. Reads may hit the wrong repo after a switch. This already exists, but bot flows make it worse; consider fixing it in the same issue.
- **The timestamp source** is `Chat.TimeKeeper.now_unix()`, as in `user.ex:55`, which matters for LWW.
- **Multiple bots per origin** are tolerated. The Observer handles each `bot_hash` independently, so don't key anything by `origin_hash` alone.
- **300-line limit and alias ordering** (`make check` → `too_long`, credo strict).

## Verification

- Unit tests (`cd chat && mix test test/chat/review_bot/`):
  - `identity_test.exs`: encode/decode round-trip; wrap/unwrap with both salts; wrong-salt and wrong-key failures; `matches_card?` false for a stranger's card.
  - `creation_test.exs`: build every batch, `Ingest.apply` each with the right `self_pop`. Assert that the `origin_bots` row exists, `VouchToken.chain_distance(origin_hash, bot_hash, "origins.<oh>.reviews.write", _)` returns `{:ok, _}`, and the device vouches exist. A combined origin+owner batch should be rejected.
  - `activations_test.exs`: valid activation is stored; wrong PoP → 403; blob for a different card → `:card_matches` error; nothing plaintext is stored in AdminDb.
  - `worker_test.exs`: `start_supervised!`. `Worker.ingest/2` inserts a row signed with the bot's PoP. `:sys.get_status/1` output contains no `sign_skey` bytes (`:binary.match` on `inspect`).
  - `observer_test.exs`:
    - activation + live row → worker running
    - tombstone row → worker stopped and activation deleted
    - activation without a row → no worker until the `{:change, :insert, row}` arrives
    - origin mismatch → no worker
  - `origin_bot_activation_controller_test.exs`.
- Regressions: `mix test test/chat/data/origin_bot_validation_test.exs test/chat/data/review_origin_gate_test.exs test/chat/pq/ingest_test.exs`, then `make check` and `make test`.
- Manual on host:
  - `make iex`, open `/electric/origin_sandbox`, create an origin, click "Enable review invitations".
  - In IEx, `Registry.lookup(Chat.ReviewBot.Registry, bot_hash)` should return a pid.
  - Restart the node: the worker should come back from AdminDb.
  - Tombstone the `origin_bots` row: the worker should stop.
- On device: `make burn_in`, repeat the flow against `buckitup-lan`, and check the logs (device-debug skill) for the worker starting and for a clean stream restart after a USB main-drive switch.
