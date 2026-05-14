# External Frontend Integration Proposal

**Status: Draft**

## Context

The current `chat/frontend/` is a standalone Vue.js SPA that handles user management and authentication. It is built with Vite, output goes to `priv/static/frontend/`, and is served by `FrontendController` at `/frontend`.

With Electric SQL, the main client has moved to a separate repository: [Buckitup-chat/chat-frontend](https://github.com/Buckitup-chat/chat-frontend). This is a much richer Vue 3 application with:

- Electric SQL (PGLite in-browser) with real-time sync
- End-to-end encryption (enigma, Lit Protocol, post-quantum)
- P2P networking (Hyperswarm, Yjs)
- Web3 / Ethereum integration
- Pinia state management

The old `chat/frontend/` is now obsolete. This proposal covers how to integrate the new external frontend into the chat application.

## Goal

Replace the old `chat/frontend/` SPA with build artifacts from `Buckitup-chat/chat-frontend`, served by Phoenix at `/frontend` using the existing infrastructure.

## Approach: external build, copy artifacts

Build `chat-frontend` externally (CI or manual) and copy its `dist/` output into `priv/static/frontend/` before Phoenix release assembly. Phoenix serves the files the same way it does today.

### Why this approach

- No submodule or monorepo coupling — frontend team works independently
- Independent release cycles — frontend can be deployed without rebuilding chat
- No changes to Phoenix serving infrastructure (`FrontendController`, `Plug.Static`, `static_paths`)
- Existing `mix assets.build` and `make frontend` pipelines stay untouched for the LiveView side
- The new frontend already builds to `dist/` and is deployed to a VPS — this is a natural extension

### Tradeoffs

- Build orchestration: CI must coordinate building `chat-frontend` and placing artifacts before `mix phx.digest`
- Version coupling is implicit — need a way to track which frontend version is deployed with which backend
- Two repos to tag/release for a full deployment

## Integration points

### Serving

No changes needed. The existing infrastructure serves the new frontend as-is:

```elixir
# FrontendController — reads priv/static/frontend/index.html
defp render_frontend(conn) do
  frontend_path = Path.join(:code.priv_dir(:chat), "static/frontend/index.html")
  conn
  |> put_resp_content_type("text/html")
  |> send_file(200, frontend_path)
end
```

```elixir
# static_paths includes "frontend"
def static_paths, do: ~w(assets fonts frontend images ...)
```

```elixir
# Plug.Static serves from priv/static/ at /
plug Plug.Static, at: "/", from: :chat, only: ChatWeb.static_paths()
```

The new frontend's `dist/` output (index.html + assets/) maps directly to this structure.

### Backend API

The new frontend connects to:

- **Electric SQL**: `/electric/v1` — already exposed by Phoenix via `Phoenix.Sync`
- **GraphQL API**: `/api` — existing Absinthe endpoint in `naive_api/`
- **WebSocket connector**: separate service for P2P signaling

The first two are already served by the chat app. The frontend's environment config needs to use relative paths (or same-origin URLs) so requests go to the Phoenix host.

### Build output mapping

Current `chat-frontend` builds to `dist/`:

```
dist/
  index.html
  assets/
    *.js
    *.css
```

This needs to land in:

```
priv/static/frontend/
  index.html
  assets/
    *.js
    *.css
```

Options:
1. Configure `chat-frontend`'s `vite.config.js` to set `base: '/frontend'` and `build.outDir` to target the chat priv directory directly (when building locally)
2. Copy `dist/*` into `priv/static/frontend/` as a build step

### Environment configuration

The new frontend uses Vite env variables for API endpoints. For embedded serving these should resolve to the Phoenix host:

```javascript
// vite.config.js — embedded profile
ELECTRIC_API_URL: '/electric/v1'
API_URL: ''           // same origin
API_SPATH: '/api'
CONNECTOR_URL: 'wss://<host>/connector'  // or separate service
```

This could be a separate Vite build mode (`--mode embedded`) or handled by runtime configuration injected into `index.html`.

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
npm run build

# Copy to chat
cp -r dist/* /path/to/chat/priv/static/frontend/
```

### CI / release

```yaml
# Pseudocode
- checkout chat-frontend at pinned version/tag
- npm ci && npm run build
- cp -r dist/* chat/priv/static/frontend/
- cd chat && mix phx.digest
- mix release
```

### Version tracking

To know which frontend is bundled with a given release:

- Option A: pin a `chat-frontend` version/tag in a file (e.g. `.frontend-version`) and have CI check it out
- Option B: use a git submodule for version pinning only (not for build integration)
- Option C: store the frontend commit hash in `priv/static/frontend/.version` during CI

## Open questions

### 1. Vite base path

Should the new frontend be built with `base: '/frontend'` so all asset references are absolute, or should it use relative paths? The old frontend used `base: '/frontend'` — keeping that is simplest.

### 2. Dev workflow

How should developers run the new frontend locally against a dev Phoenix server?

Options:
- Run `chat-frontend` dev server separately with API proxy to `localhost:4444`
- Add a `make` target that clones/pulls and builds `chat-frontend` into `priv/static/frontend/`
- Both — dev server for frontend work, make target for integration testing

### 3. Version pinning mechanism

Which approach for tracking the deployed frontend version? A `.frontend-version` file checked into the chat repo is explicit and simple. A submodule adds git tooling but more ceremony.

### 4. WebSocket connector

The new frontend uses a separate WebSocket connector service (`wss://buckitupss.appdev.pp.ua/connector`). Should Phoenix proxy this, or should it remain a separate service?

### 5. Scope of `/frontend` routes

The new frontend is a full SPA with its own router. The existing catch-all route (`/frontend/*path`) already handles this. Confirm that all new frontend routes work under the `/frontend` prefix.
