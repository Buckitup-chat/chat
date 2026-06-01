# External Frontend Integration Proposal

**Status: Draft**

## Context

The current `chat/frontend/` is obsolete. The main client has moved to a separate repository: [Buckitup-chat/chat-frontend](https://github.com/Buckitup-chat/chat-frontend) — a Vue 3 application with:

- Electric SQL (PGLite in-browser) with real-time sync
- End-to-end encryption (enigma, Lit Protocol, post-quantum)
- P2P networking (Hyperswarm, Yjs)
- Web3 / Ethereum integration
- Pinia state management

This proposal covers how to integrate the new external frontend into the chat application.

## Goal

Serve `chat-frontend` build artifacts via Phoenix. The LiveView (CubDB) UI and the new Vue SPA coexist, served by the same Phoenix Endpoint on different hostnames.

## Options considered

### Option A: `www.` subdomain (recommended)

Serve the Vue SPA at `/` on `www.buckitup.app`. LiveView stays at `/` on `buckitup.app`. API routes are host-agnostic — available on both.

| Host | Serves |
|---|---|
| `buckitup.app` | LiveView (CubDB UI) |
| `www.buckitup.app` | Vue SPA (chat-frontend) |
| both | `/electric/v1/*`, `/naive_api`, file serving |

**Why this wins:**
- Current TLS cert already covers `DNS:buckitup.app, DNS:www.buckitup.app` — no cert changes
- SPA gets a clean `/` — no Vite `base` rewriting, no Vue Router base path
- Same origin for API — no CORS changes
- Single Phoenix process — works on Nerves exactly like today
- LiveView routes completely untouched — zero migration risk
- Dev: `www.localhost:4444` resolves to `127.0.0.1` in modern browsers

**Phoenix changes required:**
- Router: add `host: "www."` scoped SPA catch-all
- `check_origin` in prod.exs: add `"//www.#{hostname}"`

**chat-frontend changes required:**
- `vite.config.js`: relative API URLs for embedded mode (`.env.embedded` or `--mode embedded`)
- No base path changes — already `/`
- No router changes — already `createWebHistory()` with no prefix

### Option B: SPA under `/frontend` path

Keep current approach — serve SPA at `/frontend`, LiveView at `/`.

**Pros:** Zero Phoenix changes, existing `FrontendController` + `Plug.Static` work as-is.

**Cons:** Requires `base: '/frontend/'` in Vite config, `createWebHistory('/frontend/')` in Vue Router, and all internal links must be prefix-aware. Awkward URL if this becomes the primary UI.

### Option C: SPA at `/`, LiveView moved to `/old`

**Rejected.** Heavy router surgery, bookmark breakage, catch-all ordering complexity, and ongoing maintenance of two frontends at `/old`.

### Option D: Separate subdomain (e.g. `app.buckitup.app`)

**Rejected.** Current Sectigo cert only covers `buckitup.app` + `www.buckitup.app`. Would require purchasing a wildcard cert (~$50-100/yr) or switching to Let's Encrypt with DNS-01 automation.

## Chosen approach: Option A (`www.` subdomain)

### Phoenix router changes

```elixir
# router.ex — add before existing "/" scope

# Vue SPA — only on www.* subdomain
scope "/", ChatWeb, host: "www." do
  pipe_through :browser
  get "/", FrontendController, :index
  get "/*path", FrontendController, :index
end

# Existing LiveView — unchanged, matches bare domain
scope "/", ChatWeb do
  pipe_through :browser
  live_session :default, on_mount: {ChatWeb.Hooks.SafariSessionHook, :default} do
    live "/", MainLive.Index, :index
    # ... all existing routes unchanged
  end
end

# API routes — no host constraint, available on both hostnames
scope "/electric/v1", ChatWeb do
  # ... unchanged
end
```

### Endpoint config changes

```elixir
# prod.exs — add www. to check_origin
check_origin: ["//#{hostname}", "//www.#{hostname}"]
```

Dev (`check_origin: false`) needs no changes.

### FrontendController

Unchanged. Already serves `priv/static/frontend/index.html`:

```elixir
defp render_frontend(conn) do
  frontend_path = Path.join(:code.priv_dir(:chat), "static/frontend/index.html")
  conn
  |> put_resp_content_type("text/html")
  |> send_file(200, frontend_path)
end
```

### Static file serving

Unchanged. `Plug.Static` already serves `priv/static/frontend/*` (JS, CSS, images) because `static_paths` includes `"frontend"`.

### chat-frontend changes

Only API URL configuration. Add `.env.embedded` to chat-frontend repo:

```bash
# .env.embedded — used with: npm run build -- --mode embedded
VITE_ELECTRIC_API_URL=/electric/v1
VITE_API_URL=
VITE_API_SURL=
VITE_API_SPATH=/naive_api
VITE_CONNECTOR_URL=wss://buckitupss.appdev.pp.ua/connector
```

No changes to:
- `base` in `vite.config.js` — stays `/`
- Vue Router — stays `createWebHistory()` with no prefix
- `index.html` — no path rewriting needed

### Build output mapping

chat-frontend builds to `dist/`:
```
dist/
  index.html
  assets/
    *.js
    *.css
```

This lands in:
```
priv/static/frontend/
  index.html
  assets/
    *.js
    *.css
```

### GraphQL path mismatch

chat-frontend uses `API_SPATH: '/api'` but Phoenix serves GraphQL at `/naive_api`. Two options:
1. Set `API_SPATH: '/naive_api'` in embedded mode (simplest)
2. Add a Phoenix route alias: `forward "/api", Absinthe.Plug, schema: NaiveApi.Schema`

Option 1 is preferred — no Phoenix changes.

## Removing the old frontend

Once the new frontend is integrated:

1. Delete `chat/frontend/` directory
2. Remove `frontend` targets from `mix assets.setup` and `mix assets.build`
3. Keep `FrontendController`, `static_paths`, and routing unchanged
4. Update `Makefile` — `make frontend` should document the new build/copy workflow

## Build workflow

### Manual / local development

```bash
# In chat-frontend repo
npm run build -- --mode embedded

# Copy to chat
cp -r dist/* /path/to/chat/priv/static/frontend/
```

Dev server: run `chat-frontend` dev server separately, access at `localhost:5173`, with Vite proxy forwarding API calls to `localhost:4444`.

### CI / release

```yaml
# Pseudocode
- checkout chat-frontend at pinned version/tag
- npm ci && npm run build -- --mode embedded
- cp -r dist/* chat/priv/static/frontend/
- cd chat && mix phx.digest
- mix release
```

### Version tracking

Pin a `chat-frontend` version/tag in `.frontend-version` file checked into the chat repo. CI checks it out at that ref. Simple, explicit, auditable.

## Dev experience

| URL | What you see |
|---|---|
| `localhost:4444` | LiveView (CubDB UI) |
| `www.localhost:4444` | Vue SPA (chat-frontend build) |
| `localhost:5173` | Vue SPA dev server (hot reload, proxies API to :4444) |

## Open questions

### 1. WebSocket connector

The new frontend uses a separate WebSocket connector service (`wss://buckitupss.appdev.pp.ua/connector`). Should Phoenix proxy this, or should it remain a separate service?

### 2. Legacy `/frontend` routes

Keep as redirect to `www.` host? Or drop entirely? Current routes:
```elixir
get "/frontend", FrontendController, :index
get "/frontend/*path", FrontendController, :index
get "/login", FrontendController, :index
get "/account", FrontendController, :index
# etc.
```

### 3. GraphQL endpoint naming

Align on `/naive_api` (current Phoenix) vs `/api` (current frontend convention). A rename in either direction is low-effort.
