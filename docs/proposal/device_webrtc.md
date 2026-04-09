
## Context

This is a proof-of-concept for connecting different browser origins (domains, `file://`) running on the **same client device**. A simple **auto-joining chat page** that connects to a single BuckitUp node (first accessible from a fallback chain) and routes all tabs sharing the same device fingerprint + IP into a common Phoenix channel room.


### Connection logic
- **Fallback chain:** try `http://localhost:4444` → `https://buckitup.app` → `https://buckitup.xyz` in order
- **Auto-connect on load** — no manual domain input
- On WebSocket open, join `room:identify:<hash>` → server returns redirect with `room:device:<ip>:<hash>`
- Join the redirected room with `user_id: "client_<origin>_<fingerprint>"` where fingerprint = FNV-1a(deviceHash + peerIp + timestamp + random)
- If a domain fails (WebSocket error/timeout), try next in chain
- Show which domain we connected to
- On disconnect from active server, stop internal reconnect and restart full fallback chain
- During probing, auto-reconnect is disabled (`_closed = true`) to prevent retry storms

### Device fingerprint
- FNV-1a 32-bit hash of `maxTouchPoints | devicePixelRatio | timezone`
- 8-char hex output
- Signals chosen for cross-browser stability on same device (cores, screen, platform excluded — they vary between browsers)
- Parts logged to console for debugging
- No `crypto.subtle` dependency — works on `file://` URLs
- `fnv1a()` extracted as shared utility, reused for both device hash and client ID generation

### Client ID
- Format: `client_<origin>_<fingerprint>` (e.g. `client_buckitup.app_3f7a2b1c`, `client_local_3f7a2b1c`)
- Origin = `location.hostname` or `"local"` for `file://` — identifies which domain the page is served from
- Fingerprint = FNV-1a(deviceHash + peerIp + timestamp + random) — unique per session
- IP extracted from server-assigned room name (`device:<ip>:<hash>`)

### Chat UI
- Status bar at top: connected domain + room name + device hash
- Simple IRC-style chat log: timestamp, sender tag, message text
- Text input + send button at bottom
- Messages sent via `signal` event with `{ type: "message", text }` to `"all"`
- Incoming `signal` events with `type: "message"` displayed in log
- `user_joined` / `user_left` events shown as system messages
- Ping/pong handling stays (auto-reply pong to ping)

### Removed
- Domain list management UI (add/remove domains)
- Bridge toggle and relay logic (single server, no bridging)
- localStorage domain persistence
- Multi-domain rendering

### Kept (from PhxSocket/PhxChannel mini-client)
- The minimal Phoenix Channel v2 JSON protocol client — reuse as-is
- Heartbeat, reconnect with exponential backoff
- `esc()` helper

## How it works

```
  Same phone (IP: 192.168.1.42, deviceHash: a1b2c3d4)
  ┌─────────────────────────────────────────────────────────────────┐
  │                                                                 │
  │  Tab 1: buckitup.app            Tab 2: file:// local            │
  │  ┌─────────────────────┐        ┌─────────────────────┐         │
  │  │ /dev/device_webrtc  │        │ /dev/device_webrtc  │         │
  │  │                     │        │                     │         │
  │  │ hash = a1b2c3d4     │        │ hash = a1b2c3d4     │         │
  │  │ userId = client_    │        │ userId = client_    │         │
  │  │  buckitup.app_7f3e  │        │  local_9a2c         │         │
  │  └────────┬────────────┘        └────────┬────────────┘         │
  │           │                              │                      │
  └───────────┼──────────────────────────────┼──────────────────────┘
              │ ws://                         │ ws://
              │                              │
              ▼                              ▼
    ┌─────────────────────────────────────────────────────┐
    │          BuckitUp Node (localhost:4444)             │
    │                                                     │
    │  1. join "room:identify:a1b2c3d4"                   │
    │     → {:error, redirect: "device:192.168.1.42:a1b2c3d4"}
    │                                                     │
    │  2. join "room:device:192.168.1.42:a1b2c3d4"        │
    │     → {:ok}                                         │
    │                                                     │
    │  ┌────────────────────────────────────────────┐     │
    │  │  Phoenix PubSub                            │     │
    │  │  topic: "room:device:192.168.1.42:a1b2c3d4"│     │
    │  │                                            │     │
    │  │  subscribers:                              │     │
    │  │    • client_buckitup.app_7f3e              │     │
    │  │    • client_local_9a2c                     │     │
    │  └────────────────────────────────────────────┘     │
    │                                                     │
    │  Tab 1 pushes signal {type: "message", text: "hi"}  │
    │    → broadcast_from! (excludes sender)              │
    │    → Tab 2 receives it                              │
    │                                                     │
    │  Tab 2 pushes signal {type: "message", text: "hey"} │
    │    → broadcast_from!                                │
    │    → Tab 1 receives it                              │
    └─────────────────────────────────────────────────────┘


  Connection sequence per client:

  Client                          Server
    │                               │
    │──── WebSocket connect ───────→│
    │                               │
    │──── phx_join                  │
    │     "room:identify:a1b2c3d4"  │
    │                          ────→│
    │                               │── look up peer IP
    │                               │   from connect_info
    │    {:error,                   │
    │     reason: "redirect",  ←────│
    │     room: "device:            │
    │       192.168.1.42:a1b2c3d4"} │
    │                               │
    │──── phx_join                  │
    │     "room:device:192..."      │
    │     {user_id:            ────→│
    │      "client_local_9a2c"}     │── subscribe to PubSub
    │                               │
    │    {:ok}                 ←────│
    │                               │── broadcast user_joined
    │                               │
    │◄──── user_joined ─────────────│  (other peers notified)
    │                               │
    │──── signal ──────────────────→│── broadcast_from!
    │     {to: "all",               │
    │      data: {type: "message",  │
    │             text: "hello"}}   │
    │                               │──→ all other subscribers
    │                               │
```

## Server-side (no changes needed)
The existing `webrtc_channel.ex` already supports:
- `room:identify:<hash>` → redirect with IP-based room (`webrtc_channel.ex:9-12`)
- `room:*` join with user_id (`webrtc_channel.ex:14-33`)
- `signal` event broadcast via `broadcast_from!` (`webrtc_channel.ex:50-66`)
- `user_joined` / `user_left` broadcasts

Endpoint already has `check_origin: false` and `connect_info: [:peer_data]`.

## Resolved issues
- **wss on localhost:** localhost uses `http://` → `ws://`, not `wss://`
- **Retry storm:** probing sockets had auto-reconnect enabled, causing parallel retry loops for all failed domains
- **crypto.subtle on file://:** not available outside secure context, replaced with FNV-1a
- **Same userId across tabs:** peers with identical hash filtered each other's messages — fixed with unique client ID: `client_<origin>_<fnv1a(hash+ip+time+random)>`

## Verification
1. `cd chat && make iex` — start dev server
2. Open `/dev/device_webrtc` in browser
3. Should auto-connect to `localhost:4444`, show device hash and room name
4. Open same page in another browser/incognito — both should land in same room
5. Type messages — both sides should see them in the chat log
6. Kill localhost → page should fall back to next domain in chain (if accessible)
