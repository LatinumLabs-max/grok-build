#!/usr/bin/env bash
# ============================================================================
# Grok Build — headless runner (grok -p) for scripting / CI
#
# The WebSocket server (entrypoint.sh) is for interactive clients. THIS script
# is the non-interactive path: one prompt in, structured result out, faithful
# exit code — for CI review gates, batch jobs, and one-off automation.
#
# Run it inside the deployed image:
#     railway run deploy/headless-run.sh "Summarize the changes in this repo"
#     docker exec -it <container> headless-run.sh --gate "Review staged changes"
# or use it as a template in your own CI.
#
# stdout carries only the model result (or JSON); all logs go to stderr, so the
# output stays parseable.
# ============================================================================
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage:
  headless-run.sh [options] "PROMPT"
  headless-run.sh [options] --prompt-file PATH

Options:
  --format FMT     plain | json | streaming-json         (default: json)
  --model NAME     model id                               (default: config.toml)
  --cwd PATH       working directory for the run          (default: cwd)
  --yolo           auto-approve tool actions (unattended writes/commands)
  --gate           review-gate mode: exit 0 iff the response begins with "OK",
                   otherwise print the response and exit 1 (implies --format json)
  --prompt-file P  read the prompt from a file instead of an argument
  --               pass all remaining args straight through to grok
Environment:
  XAI_API_KEY      required
EOF
}

FORMAT="json"
MODEL=""
CWD=""
YOLO=0
GATE=0
PROMPT=""
PROMPT_FILE=""
PASSTHROUGH=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --format)      FORMAT="$2"; shift 2 ;;
    --model)       MODEL="$2"; shift 2 ;;
    --cwd)         CWD="$2"; shift 2 ;;
    --yolo)        YOLO=1; shift ;;
    --gate)        GATE=1; FORMAT="json"; shift ;;
    --prompt-file) PROMPT_FILE="$2"; shift 2 ;;
    -h|--help)     usage; exit 0 ;;
    --)            shift; PASSTHROUGH+=("$@"); break ;;
    -*)            echo "Unknown option: $1" >&2; usage; exit 2 ;;
    *)             PROMPT="$1"; shift ;;
  esac
done

if [[ -z "${XAI_API_KEY:-}" ]]; then
  echo "FATAL: XAI_API_KEY is not set." >&2
  exit 1
fi
if [[ -z "$PROMPT" && -z "$PROMPT_FILE" ]]; then
  echo "FATAL: no prompt given." >&2
  usage
  exit 2
fi

# Build the grok invocation. Containers are immutable — never self-update.
cmd=(grok --no-auto-update --output-format "$FORMAT")
[[ -n "$MODEL" ]]        && cmd+=(--model "$MODEL")
[[ -n "$CWD" ]]          && cmd+=(--cwd "$CWD")
[[ "$YOLO" -eq 1 ]]      && cmd+=(--yolo)
if [[ -n "$PROMPT_FILE" ]]; then
  cmd+=(--prompt-file "$PROMPT_FILE")
else
  cmd+=(-p "$PROMPT")
fi
[[ ${#PASSTHROUGH[@]} -gt 0 ]] && cmd+=("${PASSTHROUGH[@]}")

echo "Running: ${cmd[*]}" >&2

if [[ "$GATE" -eq 1 ]]; then
  # Review-gate: capture JSON, pull the response text, pass iff it starts "OK".
  # Requires jq (present in the deployment image).
  out="$("${cmd[@]}")"
  text="$(printf '%s' "$out" | jq -r '.text // empty')"
  if [[ -z "$text" ]]; then
    echo "GATE: no response text (raw output below)" >&2
    printf '%s\n' "$out" >&2
    exit 1
  fi
  if [[ "$text" == OK* ]]; then
    echo "GATE: pass" >&2
    exit 0
  fi
  echo "GATE: fail — issues reported:" >&2
  printf '%s\n' "$text"
  exit 1
fi

# Normal run: stream grok's output straight through, preserving its exit code.
exec "${cmd[@]}"
