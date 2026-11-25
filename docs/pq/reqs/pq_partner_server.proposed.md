# Partner server with its own interface (YourTake)

**Status:** proposed, 2026-11-25.
**Checked against:** `chat` `main` @ c2ae5b78, `platform` `main` @ e7d19f6,
`@buckitup/pq-client` 1.1.0 (`pq-library` `main` @ b723b10), `chat-frontend`
`main` @ 5a9c357.
**Builds on:** `pq_partner_venue_messaging.proposed.md` (roles, access model,
guest admission, venues, phases) and `../external_client.md` (wire contract).
Everything there still applies; this document covers where the partner's server
runs, what web interface it serves, and how it is set up and kept up to date.

## Goal

YourTake runs an unmodified BuckitUp server on its own domain. The server serves
YourTake's web interface — guest and venue-owner screens built on
`@buckitup/pq-client` — instead of `chat-frontend`.

Two deployments, in this order:
1. **Cloud** (first): the `chat` release on a host, deployed like our staging
   (`.github/workflows/deploy-staging.yml`).
2. **Device**: a BuckitUp firmware image (`platform`), built by BuckitUp with
   the partner's interface and domain.

## Out of scope

- Protocol, access model and guest admission: see the messaging requirement.
- Narrowing a guest's write right to one venue: the backend cannot
  (`write_gate.ex:73-75`, `vouch_token.ex:96-101`); accepted there.
- Isolation of organisations on a shared LAN. A device finds every BuckitUp
  server on its subnet and syncs with it (`lan_detection.ex`); there is no
  organisation identifier. Not needed while the partner runs in the cloud.
- The partner's Wi-Fi access point settings.

## What works today

| Piece | State |
|---|---|
| Wire contract | `/electric/v1/*`: `challenge`, `ingest`, `ingest_each`, `shapes`, `read_session`, `device_identity`; CORS open (`router.ex:33-41`) |
| Serving an interface | Any static build: `/app/*` returns `priv/static/app/index.html`, other paths redirect to `/app/` (`router.ex:297-307`, `frontend_controller.ex:5`) |
| Cloud | Build the interface, copy `dist/` to `priv/static/app`, build the release with `DOMAIN`, `SECRET_KEY_BASE`, `DATABASE_URL` (as staging does) |
| Device | `CHAT_FRONTEND_DIR=<dir> DOMAIN=<domain> make image` in `platform` builds `<dir>` into the image (`platform/Makefile:52-59`, `chat/Makefile:87-93`); the certificate comes from `../cert/<domain>/` at build time |
| Passkeys | The relying party is the page's host name: the domain is permanent for a deployment, a vault made on one domain does not open on another |

### SDK coverage (1.1.0)

| Feature | SDK | Note |
|---|---|---|
| Row signing, request proof, transport with the server URL as a parameter | yes | `rows`, `challengeProof`, `transport` |
| User card, PRF vault with keys only in memory | yes | `identity.publishUserCard`, `vault` |
| Dialogs: keys, messages, revisions | yes | `dialogs` |
| Guest admission and revocation by vouch | yes | `vouch.issueVouch` / `retractVouch` |
| Venue creation, venue keys in the owner's User Storage | yes | `origins`, slot `origins` |
| Owner and venues in one session | yes | `identity.createIdentitySession` |
| Owner on a second device | **W6** | Backup format, its password encryption and the device-link relay are in `chat-frontend` only |
| Notifications to the venue owner | partner | `subscribeShape` on `dialog_keys` / `dialog_messages`; the partner's service by design |
| Key-only sign-in (R-7) | partner | `identityKeysFromSecrets`; inside the partner's app by design |

`origins`, `vouch`, `createIdentitySession` and `createUserStorage` are covered
by the SDK's tests against a fake server; no application uses them yet. Phase 2
acceptance of the messaging requirement first runs on the partner's server.

## Who updates what

- **The interface** is the partner's: they build it with the SDK version they
  choose and ship it to their server (W1). SDK releases reach them through npm.
- **The server** is ours: security and protocol fixes reach the partner as a new
  `chat` release (cloud) or a new image built by BuckitUp (device). The partner
  does not take our interface with it.

## Required work

### W1. The interface as an input — chat, platform

- **Runtime path.** `:chat, :frontend_dir` (env `FRONTEND_DIR`), default
  `priv/static/app`. `FrontendController`, `review_token_controller.ex:133` and
  a `Plug.Static` at `/app` read it at runtime. The release then serves the
  partner's interface from a directory outside the release, and the interface
  is updated without a new release or image.
- **Who may replace it.** Whoever replaces the interface controls the page that
  opens passkeys and vaults, so on a device only the server owner may upload a
  new interface (admin page, W4), as an archive signed by a release key whose
  public half is set at build time. In the cloud, the directory is the host
  operator's.
- **Image build.** The rebuild stamp and the firmware version read
  `../chat-frontend` (`platform/Makefile:49`, `frontend_version.sh`), so with
  `CHAT_FRONTEND_DIR` set, a changed interface is not rebuilt into the image
  and the version names the wrong commit. Both read `CHAT_FRONTEND_DIR`.
- **Contract for the partner:** a static build with `base: '/app/'` and
  `index.html`; the server is the page's own origin; everything the interface
  loads is in the build (devices may have no internet).

### W2. Secrets per deployment — chat, platform

- `secret_key_base` signs and encrypts Phoenix cookies, CSRF tokens and LiveView
  sessions. `config/prod.exs` falls back to a literal when `SECRET_KEY_BASE` is
  unset, and the firmware sets a literal (`platform/config/platform/target.exs:261`):
  every such server shares one key that is in the repository. Today the session
  holds only browser details, so nothing is exposed yet; any future session or
  token would be forgeable.
- Required: in the cloud, the release refuses to start without
  `SECRET_KEY_BASE`; on a device, the key is generated on first boot and kept
  on the device.

### W3. First owner — chat

The first user card written to a fresh server becomes its owner
(`owner_bootstrap.ex:10-18`). A cloud server is reachable as soon as it starts,
so "first" is a race.

- Required: an optional `OWNER_USER_HASH` (env / `:chat, :owner_user_hash`).
  When set, only a card with that `user_hash` can become the owner; other cards
  are stored as usual and never become the owner. When unset, today's rule.
- Procedure (cloud and device):
  1. Create the YourTake administrator account in the partner's interface on
     any device; note its `user_hash` (known from its keys before any server
     sees it).
  2. Deploy with `OWNER_USER_HASH` set.
  3. Sign in as the administrator; check `GET /electric/v1/device_identity`
     returns it as `admin`.
  4. Set the access mode on the admin page (W4).

### W4. Admin and debug surfaces — chat

- `/electric/*` sandboxes, `/dashboard`, `/log`, `/db_log`, `/data_keys`,
  `/reset`, `/naive_api_console` are served on every host with no guard
  (`router.ex:90-99, 145-167, 272-284`).
- The admin sandbox signs the owner in by uploading the owner's identity file,
  secret keys included, to the server. `/electric/user_sandbox` registers an
  owner whether or not its ingest succeeded (`user_sandbox_live/router.ex:238`)
  and does not check that the uploaded secret keys match the public ones.
- Required:
  - Sandboxes and debug routes are off in `prod` unless enabled by a setting;
    off answers 404.
  - One admin page stays: access mode, sync sources, interface upload (W1),
    firmware update (W5). It answers only the server owner or holders of
    `device.<id>.admin`, proven by a signed challenge
    (`invariants/01_proof_of_possession.md`), never by uploading secret keys.

### W5. Images for partner devices — platform, chat

- BuckitUp builds the images. The certificate is added at build time, so a
  certificate renewal is a new image: public certificates are limited to 200
  days since 2026-03-15 and to 100 days from 2027-03-15.
- The admin "GitHub upgrade" form installs the newest `.fw` from
  `Buckitup-chat/platform` releases (`github_firmware_upgrade_form.ex:7`). On a
  partner device it would install our image, with our interface and domain.
  The releases URL is a build setting; a partner image points to the partner's
  channel.
- An image carries the domain's TLS private key and the SSH keys that may log
  in to the device (`target.exs:37-53`). It is not published where anyone can
  download it.

### W6. Owner on a second device — SDK

Move into `@buckitup/pq-client`: the backup format (`backupContents.ts`), its
password encryption (`backupCrypto.ts`) and the device-link relay
(`deviceLink/room.ts`). `chat-frontend` consumes them from the SDK. Subaccounts
across domains use the same.

## Acceptance

- [ ] Cloud: a release with `FRONTEND_DIR` pointing at the partner's build
      serves it at `https://<domain>/app/`; replacing the directory's contents
      changes the interface without a restart.
- [ ] A release without `SECRET_KEY_BASE` in `prod` does not start.
- [ ] With `OWNER_USER_HASH` set, a card from another account written first does
      not become the owner; the administrator's card does.
- [ ] In `prod`, sandboxes and debug routes answer 404; the admin page answers
      only the owner (or a `device.<id>.admin` holder) and never asks for secret
      keys.
- [ ] Device: an image built with the partner's interface names its commit in
      the version; the interface uploaded on the admin page with a valid
      signature replaces it, an unsigned one is refused; the upgrade form offers
      only the partner's channel.
- [ ] The SDK exports backup export/import and the device-link relay;
      `chat-frontend` uses them; the owner's account moves to a second device by
      either.
- [ ] Phase 2 of the messaging requirement passes on the partner's cloud server.
