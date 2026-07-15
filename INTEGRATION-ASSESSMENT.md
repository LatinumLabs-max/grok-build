# Grok Build — Integration Assessment for Latinum Labs

An evaluation of how this repository (SpaceXAI's open-source `grok` coding agent,
Apache-2.0) can benefit our Claude Code sessions, Railway deployments, and
software builds. Compiled 2026-07-15 from a full sweep of the workspace
(~70 crates), the 24-chapter user guide, and the agent runtime source.

## Licensing baseline

- **Apache 2.0** throughout (root `LICENSE`, workspace `license` fields), with a
  patent grant. Commercial reuse is unrestricted; obligations are attribution,
  carrying the license/`THIRD-PARTY-NOTICES`, and noting changes to modified
  files. **No trademark rights** — we can use the code, not the Grok/xAI branding.
- **Nothing is published to crates.io.** All internal deps are path deps, so
  reuse means vendoring crate directories (repointing `workspace = true` deps to
  the pinned versions listed in the root `Cargo.toml`).

## 1. Benefits for our Claude Code sessions

### 1a. Our `.claude/` config is a portable asset — keep investing in it

Grok Build ships a first-class **Claude Code compatibility layer**
(`docs/user-guide/05-configuration.md`, `[compat.claude]`, all cells default-on):

| Claude Code surface | Read by Grok Build |
|---|---|
| `.claude/skills/` + `~/.claude/skills/` (SKILL.md, same frontmatter style) | yes |
| `CLAUDE.md` / `CLAUDE.local.md` / `AGENTS.md` (all variants, all levels) | yes |
| `.mcp.json` (project) and `~/.claude.json` (MCP servers) | yes |
| `.claude/settings.json` hooks (same JSON schema, tool-name aliases `Bash`→`run_terminal_command` etc.) | yes |
| `.claude/settings.json` / `settings.local.json` `permissions` rules | yes |
| `.claude/rules/`, `.claude/plugins/`, legacy `commands/*.md` | yes |

Cursor and (partially) Codex surfaces are read too. **Implication:** Claude
Code's config conventions are becoming the cross-vendor standard. We should
standardize all repo-level agent config in Claude-native formats
(`.claude/skills`, `CLAUDE.md`, `.mcp.json`, `settings.json` hooks/permissions)
— it buys us zero-cost portability to Grok Build, Cursor-compatible tools, and
anything else that adopts the same reader. Avoid tool-proprietary formats for
anything we want to keep.

Not compatible: Grok does **not** import `.claude/agents/*.md` subagent
definitions (its `compat.claude.agents` cell maps to CLAUDE.md memory files).

### 1b. It can run Claude models

`[model.<name>]` custom models support `api_backend = "messages"` (Anthropic
Messages API) with `base_url = "https://api.anthropic.com/v1"` — so the Grok
TUI/harness can be evaluated head-to-head against Claude Code on the same
model, or used as a secondary harness with our Anthropic keys
(`docs/user-guide/11-custom-models.md`).

### 1c. Feature ideas worth borrowing into our Claude Code workflows

- **Cross-session semantic memory** (`13-memory.md`): SQLite FTS5 + vector
  hybrid search, temporal decay, `/dream` consolidation, pre-compaction
  `/flush`. We could approximate with a memory MCP server.
- **Multi-agent dashboard** (`23-dashboard.md`): single-screen supervisor for
  parallel sessions — peek, reply, answer permission prompts from the overview.
- **Headless `--best-of-n N` and `--check`/`--self-verify`** flags: run a task
  N ways and pick the best; append a verification loop. Easy to script around
  Claude Code headless mode ourselves.
- **Durable scheduler + `monitor` tool** (`20-background-tasks.md`):
  `scheduler_create {durable: true}` persists recurring tasks across sessions;
  `monitor` streams long-running command output line-by-line as notifications.
- **Content-free OpenTelemetry export** (`24-monitoring-usage.md`): versioned
  schema, fail-closed redaction, standard OTLP env vars — a good template for
  fleet-level agent usage monitoring.
- **Exact-integer cost accounting**: headless JSON reports
  `total_cost_usd_ticks` (1 USD = 10^10 ticks) plus `cost_is_partial` flags —
  a pattern to adopt for our own billing reconciliation of agent runs.

## 2. Benefits for our Railway deployments

### 2a. Running the agent itself as a service (if we adopt it)

- **Scripting/CI path:** `grok -p "<prompt>" --output-format json|streaming-json
  [--json-schema <schema>]`, auth via `XAI_API_KEY` env var (no browser; also
  RFC 8628 device-code and pluggable `auth_provider_command`). Clean stdout
  (logs to stderr), exit codes 0/1/130/143, token+cost usage in the JSON.
  Container guidance exists (read-only `~/.grok`, `GROK_DISABLE_AUTOUPDATER=1`).
- **Server mode:** `grok agent serve --bind ... --secret ...` — axum WebSocket
  server with bearer-secret auth, reconnect-safe.
- **Relay dial-out mode:** `grok agent headless --grok-ws-url wss://relay/...` —
  the agent connects OUT to a relay so browsers reach it without inbound ports.
- No Dockerfile/CI ships in the repo; we'd write our own image around the
  musl static binary.
- Data-governance note: using the hosted grok.com backend sends code to xAI;
  the custom-model config can point it at our own endpoints instead.

### 2b. Architecture patterns to copy into our own services

- **Leader process + ACP replay** (`xai-grok-shell/src/leader/`): a shared
  backend on a Unix socket, multiple clients, length-prefixed JSON frames, and
  crash-resilient reconnect that replays cached `initialize`/`session/*` state.
  A strong blueprint for any long-lived stateful service behind flaky clients.
- **ACP (Agent Client Protocol) over stdio** (`agent-client-protocol` 0.10.x,
  V1): the standard way to embed an agent in editors/apps; SDKs exist for
  TS/Rust/Python/Go/Kotlin. If we ever expose our own agent, speak ACP.
- **Turn-boundary checkpoint/rewind** (`xai-grok-workspace/src/session/
  checkpoint.rs`): filesystem snapshot + hunk delta + git HEAD bundled per
  prompt index, restored atomically.

### 2c. Crates to vendor into our Rust services (ranked)

1. **`xai-circuit-breaker`** (`crates/common/`) — sliding-window circuit
   breaker + retry policy, only dep is `log`, pluggable clock/observer.
   Drop-in resilience for any Railway service (compare with `failsafe`/`tower`).
2. **`xai-grok-compaction`** — transport-agnostic LLM context-compaction
   engine, zero internal deps, clean trait seams. High value if we build our
   own agent loops on the Anthropic API.
3. **`xai-grok-sandbox`** — Landlock (Linux) / Seatbelt (macOS) process
   sandbox + per-child seccomp network blocking. 1 internal dep. Kernel-level
   guardrails for anything that executes untrusted commands.
4. **`xai-codebase-graph`** — tree-sitter go-to-def/find-refs engine
   (Rust/TS/Python/Go) with a `code-graph` CLI; 1 easy internal dep.
5. **`xai-crash-handler`** — zero-internal-dep crash reporter for CLIs/TUIs.
6. **`xai-grok-markdown` (+`-core`)** — streaming terminal markdown renderer
   tuned for LLM output.
7. **`xai-ratatui-inline` / `xai-ratatui-textarea`** — polished, standalone
   ratatui widgets (inline chat viewport; multi-line editor).
8. **`xai-fast-worktree`** — reflink/BTRFS-snapshot git worktree pools
   (~4-crate cluster) for parallel agent/build isolation.
9. **`xai-sqlite-journal`** — picks WAL vs rollback journal by filesystem
   (NFS-safe SQLite); niche but real.
10. **`ptyctl`** — headless PTY automation with an HTTP/WS API; useful for
    TUI e2e testing.

Skip: `xai-grok-mcp` (≈9 internal deps — use upstream `rmcp` directly) and the
`xai-computer-hub-*` / `xai-tool-*` stack (coupled bespoke framework).

## 3. Benefits for our software builds

- **Hardened release recipe** (`.cargo/config.toml`): static musl targets with
  full RELRO + `noexecstack` linker hardening, `force-unwind-tables`,
  per-arch `target-cpu` tuning, jemalloc page-size env vars for aarch64.
  Directly copyable into our Rust build configs; musl static binaries also make
  minimal (scratch/distroless) Railway images.
- **Toolchain pinning policy** (`rust-toolchain.toml`): pin latest stable, bump
  one point release at a time after a soak period, re-run
  `cargo check`/`clippy --all-targets --workspace` on bump.
- **Generated workspace manifest** pattern: root `Cargo.toml` is generated and
  read-only; per-crate manifests are the source of truth — a scalable pattern
  for large workspaces.
- **`dotslash` launchers** (`bin/protoc`) for hermetic build-tool fetching
  instead of committing binaries or trusting PATH.
- **CI integration patterns** (`14-headless-mode.md`): agent-as-review-gate,
  pre-commit hook, and batch-processing examples with structured JSON output,
  `--max-turns`, tool allow/deny lists, and `--json-schema`-constrained output —
  templates that apply equally to Claude Code headless (`claude -p`) in our CI.

## Suggested next steps

1. Standardize repo agent config on Claude-native formats (`.claude/skills`,
   `CLAUDE.md`, `.mcp.json`, `settings.json` hooks/permissions) — portable
   across harnesses for free.
2. Trial-vendor `xai-circuit-breaker` into one Railway service; benchmark
   against `failsafe`/`tower` before committing.
3. Copy the musl+RELRO release profile into our Rust build template.
4. If we want a self-hosted agent worker on Railway, prototype around
   `grok -p --output-format streaming-json` with `XAI_API_KEY` (or a custom
   `[model.*]` pointing at our own endpoint), or replicate the same pattern
   with Claude Code headless.
5. Evaluate `xai-grok-compaction` + `xai-grok-sandbox` if/when we build our own
   Anthropic-API agent loops.
