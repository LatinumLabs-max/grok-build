#!/usr/bin/env bash
# ============================================================================
# Grok Build — Railway entrypoint
#
# Starts the built-in WebSocket agent server, bound to the port Railway hands
# us. Clients (editors/ACP clients or a web UI) connect over WebSocket and
# authenticate with the bearer secret.
# ============================================================================
set -euo pipefail

# Railway injects $PORT. Fall back to the CLI default port for local runs.
PORT="${PORT:-2419}"
BIND_ADDR="0.0.0.0:${PORT}"

# --- Required secrets -------------------------------------------------------
# XAI_API_KEY authenticates the agent to the xAI backend. Without it the agent
# cannot reach a model, so fail fast with a clear message instead of starting a
# server that errors on the first prompt.
if [[ -z "${XAI_API_KEY:-}" ]]; then
  echo "FATAL: XAI_API_KEY is not set." >&2
  echo "  Set it in the Railway service Variables (get a key at https://console.x.ai)." >&2
  exit 1
fi

# GROK_AGENT_SECRET is the bearer token clients present to connect. If unset,
# the server auto-generates one and prints it at startup — but on Railway that
# value is unreachable, so require an explicit, stable secret.
if [[ -z "${GROK_AGENT_SECRET:-}" ]]; then
  echo "FATAL: GROK_AGENT_SECRET is not set." >&2
  echo "  Set a strong random token in the Railway service Variables; clients" >&2
  echo "  must send the same token to connect. e.g. \`openssl rand -hex 32\`." >&2
  exit 1
fi

echo "Starting Grok Build agent server on ${BIND_ADDR}" >&2
echo "  GROK_HOME=${GROK_HOME:-~/.grok}  model default from config.toml" >&2

# clap reads --secret from $GROK_AGENT_SECRET automatically; passing it
# explicitly keeps the invocation self-documenting. exec so the agent is PID 1
# and receives SIGTERM directly (clean shutdown / exit code 143).
exec grok agent serve \
  --bind "${BIND_ADDR}" \
  --secret "${GROK_AGENT_SECRET}" \
  "$@"
