#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
NEURAL="$ROOT/neural"
APP="$ROOT/app"
BRAIN_URL="http://localhost:4001"

cleanup() {
  if [ -n "${BRAIN_PID:-}" ]; then
    kill "$BRAIN_PID" 2>/dev/null || true
    echo ""
    echo "Brain stopped."
  fi
}
trap cleanup EXIT INT TERM

# ── 1. Compile Rust NIFs if missing ──────────────────────────
if [ ! -f "$ROOT/core/target/release/libodysseus_neurons.dylib" ]; then
  echo "Compiling Rust NIFs..."
  (cd "$ROOT/core" && cargo build --release 2>&1)
  mkdir -p "$NEURAL/apps/odysseus_brain/priv"
  cp "$ROOT/core/target/release"/libodysseus_*.dylib "$NEURAL/apps/odysseus_brain/priv/"
  echo "NIFs compiled."
fi

# ── 2. Fetch Elixir deps if needed ───────────────────────────
if [ ! -d "$NEURAL/deps/plug" ]; then
  echo "Fetching Elixir deps..."
  (cd "$NEURAL" && mix deps.get 2>&1)
fi

# ── 3. Start Elixir brain in background ──────────────────────
echo "Starting Elixir brain..."
(cd "$NEURAL" && mix run --no-halt 2>&1) &
BRAIN_PID=$!

# ── 4. Wait for brain to be ready ────────────────────────────
echo -n "Waiting for brain"
for i in $(seq 1 30); do
  if curl -sf "$BRAIN_URL/health" >/dev/null 2>&1; then
    echo " ready."
    break
  fi
  echo -n "."
  sleep 1
  if [ "$i" -eq 30 ]; then
    echo ""
    echo "Brain did not start in 30s. Running TUI in standalone mode."
    BRAIN_PID=""
  fi
done

# ── 5. Start TypeScript TUI ─────────────────────────────────
if [ ! -d "$APP/node_modules" ]; then
  echo "Installing TypeScript dependencies..."
  (cd "$APP" && npm install 2>&1)
fi

echo "Starting TUI..."
(cd "$APP" && exec npx tsx src/main.ts)
