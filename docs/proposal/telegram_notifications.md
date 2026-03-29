# Telegram Notifications Proposal

## Goal

Add a special built-in bot user named `TG Notifier` that periodically scans configured dialogs and rooms and sends Telegram notifications to subscribed users.

The feature should let a BuckitUp user:

- connect their Telegram account to `TG Notifier`
- subscribe to selected dialogs and rooms
- receive Telegram notifications about new activity
- avoid duplicate notifications across polling cycles and restarts

The notifier is intentionally limited. It should not require direct access to decrypt arbitrary room or dialog history beyond what the notifier account can already see. For rooms and dialogs where it cannot read message contents, it may still notify using metadata such as message count growth, author identity if available, and the last visible message preview.

## High-level idea

`TG Notifier` is a first-class chat identity whose configuration and operational state live in `AdminDb`.

At startup the app:

- loads or creates the notifier identity
- loads Telegram bindings and subscriptions from `AdminDb`
- starts a periodic worker, for example every 10 minutes

The periodic worker:

- iterates over user subscriptions
- inspects subscribed dialogs and rooms
- determines whether there are messages newer than the last already-notified point
- sends a Telegram message if there is new activity
- records progress so the same messages are not notified twice

## Why `AdminDb`

This matches the existing architecture:

- `AdminDb` already stores admin-scoped metadata and links
- notifier configuration is system-level operational state, not end-user portable chat content
- notifier state must survive restarts even when no specific user session is active

This proposal keeps chat content in the main chat DB and stores only notifier metadata / cursors in `AdminDb`.

## User experience

### 1. Connect Telegram

A user opens a dialog with `TG Notifier` and sends a command or follows a guided flow:

- `/start`
- `/connect <telegram handle or one-time token>`

Alternative flow:

- user starts the Telegram bot first
- Telegram bot gives a one-time token
- user sends that token to `TG Notifier` inside BuckitUp

Binding should complete only after proving control of both sides.

### 2. Subscribe to a dialog or room

A user provides `TG Notifier` with links to dialogs and rooms they want monitored.

Examples:

- dialog link
- room link

The bot stores a subscription entry for each accepted link.

### 3. Receive notifications

Every polling cycle, if there is new activity, the user receives a Telegram notification containing:

- source name
- source type: dialog or room
- a BuckitUp link back to the dialog or room

### 4. Deduplication feedback in BuckitUp

After notifying, `TG Notifier` writes a message into the user ↔ notifier dialog with the format:

```
notified 12 on https://buckitup.app/room-subscription/abc123
```

Where `12` is the latest message index that was notified.

This serves two purposes:

- user-visible audit trail
- notifier-readable state anchor to avoid duplicate notifications

### 5. Unsubscribe by deletion

A user can unsubscribe from a room or dialog by deleting their message containing the subscription link in the notifier dialog.

The notifier detects deleted subscription messages during polling cycles and deactivates the corresponding subscriptions.

## Functional requirements

### Required

- special built-in user `TG Notifier`
- Telegram bot integration
- user ↔ Telegram account binding
- subscription management by dialog / room links
- periodic scan, default every 10 minutes
- duplicate suppression across restarts
- BuckitUp-side audit messages from notifier to user

### Optional for first version

- batching multiple rooms/dialogs into one TG digest message

## Scope of visibility

The notifier must respect the same access limits as the notifier identity itself.

 --- REVIEW MORE ---

### Dialogs

For a dialog to be monitored, one of these must be true:

- the notifier is explicitly part of the dialog model, or
- the dialog link is implemented as an admin-authorized subscription target that exposes only metadata needed for notifications

This is the main design decision for dialogs.

A normal private dialog between two users should not automatically become visible to a third-party notifier account.

### Rooms

For rooms, the notifier may often be able to observe only metadata unless explicitly invited or otherwise granted read capability.

For rooms where message content is unavailable, the notifier should use:

- new message count
- latest message timestamp
- latest author hash/card if resolvable
- any safe preview already exposed by existing room link mechanisms

## Important design decision: link types

The feature needs stable links for dialogs and rooms.

There are two separate link categories in the current system:

- chat links, such as `/chat/:hash`, which navigate to a dialog
- public room message links, such as `/room/:hash`, which are currently tied to a specific linked message

That is not yet sufficient as a canonical subscription model.

### Proposed new concept: subscription links

Introduce stable subscription targets distinct from message-sharing links.

#### Dialog subscription link

A dialog subscription link should identify a dialog without exposing raw dialog internals.

Possible storage:

```elixir
{{:tg_subscription_link, :dialog, link_hash}, %{dialog_key: dialog_key, created_by: user_pub_key, inserted_at: ts}}
```

Properties:

- stable across notifier polling cycles
- revocable
- can be shown/copied by the user from UI
- can be resolved by the notifier without requiring the notifier to be a normal dialog participant

#### Room subscription link

A room subscription link should identify a room as a notification source and optionally define what metadata may be exposed.

Possible storage:

```elixir
{{:tg_subscription_link, :room, link_hash}, %{room_hash: room_hash, room_pub_key: room_pub_key, created_by: user_pub_key, inserted_at: ts}}
```

This is separate from existing room message links because those are tied to one message and public-room sharing use cases.

### Why separate links

Separate subscription links avoid overloading existing sharing semantics.

They also let us:

- revoke notifier access without breaking normal shared message links
- track ownership and permissions per subscription target
- implement access rules specific to Telegram notifications

## Data model proposal

All notifier-specific persistent state should live in `AdminDb`.

### 1. Notifier identity

```elixir
{:tg_notifier_identity, notifier_identity}
```

Stores the BuckitUp identity for the special bot user.

### 2. Telegram bot configuration

```elixir
{:tg_bot_settings, %{bot_token_env: "TG_BOT_TOKEN", polling_interval_ms: 600_000, enabled: true}}
```

Do not store the raw Telegram token in `AdminDb` if it can be supplied via environment/config.

### 3. User Telegram binding

```elixir
{{:tg_user_binding, user_pub_key}, %{telegram_chat_id: tg_chat_id, telegram_username: username, status: :active, bound_at: ts}}
```

### 4. One-time binding tokens

```elixir
{{:tg_binding_token, token}, %{user_pub_key: user_pub_key, expires_at: ts}}
```

Used to prove Telegram account ownership during pairing.

### 5. Subscription links

```elixir
{{:tg_subscription_link, source_type, link_hash}, metadata}
```

Where `source_type` is `:dialog` or `:room`.

### 6. User subscriptions

```elixir
{{:tg_subscription, user_pub_key, source_type, link_hash}, %{
  label: label,
  mode: :digest,
  active: true,
  created_at: ts
}}
```

### 7. Notification cursors

```elixir
{{:tg_notification_cursor, user_pub_key, source_type, link_hash}, %{
  last_notified_index: index,
  last_notified_msg_id: msg_id,
  last_notified_at: ts
}}
```

This is the canonical machine cursor.

### 8. Delivery log

```elixir
{{:tg_notification_delivery, user_pub_key, source_type, link_hash, ts}, %{
  from_index: from_index,
  to_index: to_index,
  telegram_message_id: telegram_message_id
}}
```

Useful for auditing and debugging.

## Why keep a cursor if the notifier also writes into the dialog

The user requested that the notifier writes the last notified messages into the user ↔ notifier dialog so future runs know what was already notified.

That is a good product requirement, but using chat messages as the only state source would be fragile:

- parsing human-readable messages is brittle
- deleted or edited notifier messages would damage state recovery
- recovery becomes slower because the notifier has to scan its own dialog history

### Proposed approach

Use both:

- `AdminDb` cursor as the authoritative machine state
- notifier dialog messages as user-visible audit trail

Each Telegram notification should also produce a structured notifier message in BuckitUp, for example:

- source
- notified range
- total new messages
- Telegram delivery timestamp

If needed later, that message can carry a machine-readable payload in metadata.

## Polling flow

### Startup

1. Start `TGNotifier.Supervisor`
2. Load `:tg_bot_settings`
3. Load or create `:tg_notifier_identity`
4. Start Telegram bot client
5. Start periodic scan worker

### Periodic scan cycle

For each active subscription:

1. resolve the subscription link into a concrete dialog or room target
2. load the user's notification cursor
3. inspect target for messages newer than the cursor
4. build notification summary
5. send Telegram message
6. persist updated cursor in `AdminDb`
7. write BuckitUp audit message into user ↔ notifier dialog

### Dialog scan logic

For dialogs, the worker needs a way to enumerate messages by dialog key and compare against `last_notified_index`.

Desired output:

- newest message index
- count of messages after cursor
- last visible message preview
- latest timestamp

### Room scan logic

For rooms, the worker similarly compares current latest room message against the stored cursor.

If decryption is not possible, it should still notify with metadata only.

## Telegram delivery format

### Digest example

```text
BuckitUp notification
Source: Product Team Room
Type: room
New messages: 7
Latest activity: 2026-03-14 10:20 UTC
Last visible message: "Deploy is complete"
Open in BuckitUp: https://.../room-subscription/abcd...
```

### Metadata-only example

```text
BuckitUp notification
Source: Alice / Bob dialog
Type: dialog
New messages: 3
Latest activity: 2026-03-14 10:20 UTC
Preview: unavailable
Open in BuckitUp: https://.../chat/...
```

## Proposed modules

### Backend

- `Chat.TgNotifier`
  - public API for setup, bindings, subscriptions
- `Chat.TgNotifier.Supervisor`
  - supervises Telegram client and poller
- `Chat.TgNotifier.Poller`
  - periodic worker, default every 10 minutes
- `Chat.TgNotifier.Binding`
  - one-time token generation and binding verification
- `Chat.TgNotifier.Subscriptions`
  - create/revoke/list subscriptions
- `Chat.TgNotifier.Cursors`
  - read/write last notified position
- `Chat.TgNotifier.TelegramClient`
  - wrapper around Telegram Bot API
- `Chat.TgNotifier.SourceResolver`
  - resolves subscription link to dialog/room target
- `Chat.TgNotifier.Summarizer`
  - computes message count, preview, latest info

### UI / LiveView

- dialog action to generate dialog subscription link
- room action to generate room subscription link
- user-facing subscription management panel
- notifier dialog commands/help messages

## Integration with current codebase

### Reuse

- `Chat.AdminDb` for admin-scoped notifier metadata
- existing dialog and room data stores in main DB
- existing modal/link UI patterns for displaying shareable links
- existing GenServer poller style using `Process.send_after/3`

### New capability needed

- stable subscription link generation for dialogs
- stable subscription link generation for rooms
- message summary readers that can work from stored cursors
- Telegram Bot API adapter

## Security and privacy

### Requirements

- Telegram bot token must come from runtime config / env, not hardcoded in DB or source
- only the owning user may create or revoke their notifier subscriptions
- subscription links must be unguessable and revocable
- notifier must not escalate access beyond explicitly allowed metadata
- audit messages should avoid leaking hidden content if the notifier cannot legitimately read it

### Recommended rule

For version 1, if the notifier cannot legitimately read content, it should only send metadata notifications and never attempt content reconstruction.

## Failure handling

### Telegram unavailable

- keep cursor unchanged if delivery fails
- retry on next cycle
- record failure in logs and optionally in delivery log

### Source removed / revoked

- mark subscription inactive
- write notifier message to user dialog explaining the subscription is no longer valid

### User unbinds Telegram

- keep subscriptions but suspend delivery, or deactivate them explicitly

## Implementation phases

### Phase 1 - foundations

- create notifier identity management
- add Telegram bot client wrapper
- add user binding flow
- add `AdminDb` schemas/keys for bindings and subscriptions

### Phase 2 - subscription targets

- add stable dialog subscription links
- add stable room subscription links
- add UI actions to copy/share those links

### Phase 3 - polling and delivery

- implement poller
- implement cursor storage
- implement Telegram digest sending
- implement notifier audit messages in user dialog

### Phase 4 - UX hardening

- subscription list UI
- unsubscribe flow
- better summaries and error reporting
- optional per-subscription settings

## Open questions

### 1. Dialog access model

How should `TG Notifier` observe a private dialog without violating end-to-end expectations?

Options:

- metadata-only access through a special admin-owned subscription link
- explicit 3-party notifier dialog model
- no private dialog support in v1, rooms only

This is the most important product/architecture question.

### 2. Room preview rules

Should room notifications include decrypted last-message preview only when the notifier is an invited room member, and otherwise fall back to metadata-only?

### 3. Link UX

Should users manually paste links into the notifier dialog, or should the UI have a direct `Notify me in Telegram` action that creates the subscription automatically after binding?

### 4. Cursor source of truth

This proposal recommends `AdminDb` as source of truth and BuckitUp notifier messages as audit trail. Confirm that this matches the intended behavior.

### 5. Polling interval

Default is `10 min`, but should this be:

- global only
- per user
- per subscription

## Recommendation

For the first implementation, keep the design narrow:

- support Telegram binding
- support room subscriptions first
- use stable notifier-specific subscription links
- store authoritative cursor state in `AdminDb`
- mirror deliveries into the user ↔ notifier dialog as audit messages
- keep dialog support behind an explicit decision on privacy/access semantics

This yields a useful first version without forcing a risky privacy model for private dialogs.
