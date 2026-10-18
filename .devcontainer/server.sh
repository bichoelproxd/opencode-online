#!/usr/bin/env bash
# Starts an opencode server inside a GitHub Codespace so the GitHub Pages web app can connect to it.
#   server.sh start  install opencode, start the server and make its port public
#   server.sh show   print the address and password to paste into the web app
set -euo pipefail

PORT=4096
STATE="$HOME/.opencode-server"
BIN="$HOME/.local/bin"
mkdir -p "$STATE" "$BIN"
export PATH="$BIN:$PATH"

address() {
  echo "https://${CODESPACE_NAME}-${PORT}.${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN}"
}

start() {
  if ! command -v opencode >/dev/null 2>&1; then
    curl -fsSL https://opencode.ai/v2/install | XDG_BIN_DIR="$BIN" bash
  fi

  [ -s "$STATE/password" ] || openssl rand -hex 16 >"$STATE/password"

  # The web app is served from https://<owner>.github.io, which the server must allow.
  local owner
  owner="$(echo "${GITHUB_REPOSITORY%%/*}" | tr '[:upper:]' '[:lower:]')"

  if ! pgrep -f "opencode serve" >/dev/null 2>&1; then
    OPENCODE_PASSWORD="$(cat "$STATE/password")" setsid nohup opencode serve \
      --hostname 0.0.0.0 --port "$PORT" --cors "https://${owner}.github.io" \
      >"$STATE/server.log" 2>&1 </dev/null &
  fi

  # A private port needs a GitHub login, which the web app cannot send, so the port is made public.
  # The server password still protects it.
  for _ in $(seq 1 60); do
    (echo >"/dev/tcp/127.0.0.1/$PORT") 2>/dev/null && break
    sleep 1
  done
  gh codespace ports visibility "$PORT:public" -c "$CODESPACE_NAME" ||
    echo "Could not make port $PORT public. Set it to Public in the Ports tab."
}

show() {
  if [ ! -s "$STATE/password" ]; then
    echo "The opencode server is still starting. Run: bash .devcontainer/server.sh show"
    return
  fi

  echo
  echo "opencode server"
  echo "  Address:  $(address)"
  echo "  Password: $(cat "$STATE/password")"
  echo
  echo "Paste both into Add server in the web app."
}

case "${1:-}" in
  start) start ;;
  show) show ;;
  *) echo "usage: server.sh start|show" >&2; exit 1 ;;
esac
