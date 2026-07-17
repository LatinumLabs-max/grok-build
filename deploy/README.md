# Deploying Grok Build on Railway

This directory packages Grok Build as a self-hosted **WebSocket agent server**
(`grok agent serve`) on [Railway](https://railway.com). The server persists
across client reconnections, authenticates clients with a bearer secret, and
uses the xAI backend for inference.

> **Branding note.** The upstream code is Apache-2.0 but grants **no trademark
> rights** — you may run and modify the code, but the Grok/xAI name and logo
> are not licensed to you. This deployment keeps the internal `grok` binary
> name and does not re-badge anything as your own product.

## What ships in the image

| File | Purpose |
|------|---------|
| [`../Dockerfile`](../Dockerfile) | Two-stage build: compile `xai-grok-pager` → slim Debian runtime |
| [`../railway.json`](../railway.json) | Railway build/deploy config (Dockerfile builder, restart policy) |
| [`../.dockerignore`](../.dockerignore) | Trims the build context (keeps `.md` — the CLI embeds its docs) |
| [`entrypoint.sh`](entrypoint.sh) | Binds `grok agent serve` to `0.0.0.0:$PORT`; requires the two secrets below |
| [`grok-home/config.toml`](grok-home/config.toml) | **Your** baked config defaults + theme |
| [`grok-home/pager.toml`](grok-home/pager.toml) | **Your** baked appearance/layout tweaks |

## Deploy steps

1. **Create a Railway project** from this repository (New Project → Deploy from
   GitHub repo). Railway reads `railway.json` and builds with the `Dockerfile`.
   No start command is needed — the image `ENTRYPOINT` handles it.

2. **Set the service Variables** (Railway dashboard → your service → Variables):

   | Variable | Required | Notes |
   |----------|----------|-------|
   | `XAI_API_KEY` | ✅ | xAI API key from <https://console.x.ai>. |
   | `GROK_AGENT_SECRET` | ✅ | Bearer token clients must present. Generate with `openssl rand -hex 32`. |
   | `RUST_LOG` | optional | Log verbosity (`info` default; `debug` to troubleshoot). |
   | `PORT` | auto | Injected by Railway; the entrypoint binds it. Don't set by hand. |

   The entrypoint **fails fast** if either required secret is missing, so a
   misconfigured deploy stops immediately instead of erroring on first prompt.

3. **Expose the service.** In Settings → Networking, generate a domain (or add a
   custom one). Railway routes it to the container's `$PORT`. Because this is a
   WebSocket server there is **no HTTP health-check path** — that's intentional;
   `railway.json` uses an `ON_FAILURE` restart policy instead.

4. **Connect a client.** Point any ACP/WebSocket client at
   `wss://<your-domain>` and send `GROK_AGENT_SECRET` as the bearer token. See
   the agent-mode guide:
   [`../crates/codegen/xai-grok-pager/docs/user-guide/15-agent-mode.md`](../crates/codegen/xai-grok-pager/docs/user-guide/15-agent-mode.md).

## Customizing your design choices

Your two customization files are baked into the image at build time, so editing
them and redeploying is all it takes.

- **Theme / colors** — [`grok-home/config.toml`](grok-home/config.toml)
  `[ui].theme` picks one of the five built-in themes (`groknight`, `grokday`,
  `tokyonight`, `rosepine`, `oscura`). **Fully custom RGB themes are not
  supported** — the theme system owns the color slots internally. Finer control
  (bullets, block styling, scrollbar, padding, animation) lives in
  [`grok-home/pager.toml`](grok-home/pager.toml).

  These are **client-side rendering** settings. `grok agent serve` streams
  structured events and the connecting client draws them, so the theme applies
  when you run the TUI inside the container (`railway run grok`, or
  `docker exec -it <container> grok`) — not to the wire protocol itself.

- **Config defaults** — the rest of
  [`grok-home/config.toml`](grok-home/config.toml): default model, feature
  toggles (telemetry off, indexing on), auto-compact threshold, bash timeouts,
  etc. These **do** govern the running server and every session it starts.

## Session persistence (optional)

Sessions, logs, and memory live under `$GROK_HOME` (`/home/grok/.grok`). The
container filesystem is ephemeral, so to keep transcripts across redeploys add
a **Railway Volume** mounted at `/home/grok/.grok`. Without a volume the server
runs fine but session history resets on every deploy.

## Notes & limitations

- **First build is long.** The image compiles the full CLI crate closure
  (~70 crates). BuildKit cache mounts in the `Dockerfile` make later builds
  fast; the first one is a cold Rust release build.
- **Data governance.** With `XAI_API_KEY` the agent sends prompts/code to the
  xAI backend. To keep traffic on your own infra instead, add a `[model.*]`
  block in `config.toml` pointing `base_url` at your endpoint and switch
  `[models].default` to it (see the custom-models guide).
- **Runtime toolchains.** The runtime image carries `git`, `curl`, `ripgrep`
  and a minimal userland. If your workloads need language toolchains (Node,
  Python, etc.), add them to the runtime stage of the `Dockerfile`.
