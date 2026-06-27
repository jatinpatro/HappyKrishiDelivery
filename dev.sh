#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# dev.sh — Local development starter
#
# Runs both services. Start each in a separate terminal if preferred:
#
#   BACKEND (Terminal 1):
#     cd happykrishi_backend ; npm run dev
#     
#
#   FLUTTER (Terminal 2):
#     cd happykrishi_flutter ; flutter run -d chrome \
#       --dart-define=API_BASE_URL=http://localhost:3000 \
#       --dart-define=WS_BASE_URL=ws://localhost:3000/ws
#
#     
# Or just run:  bash dev.sh
# ─────────────────────────────────────────────────────────────────────────────

#cd /Users/I503151/Desktop/HappyKrishi/HappyKrishiDelivery/happykrishi_backend && npm run dev
#cd /Users/I503151/Desktop/HappyKrishi/HappyKrishiDelivery/happykrishi_flutter && flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:3000 --dart-define=WS_BASE_URL=ws://localhost:3000/ws


set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKEND_DIR="$SCRIPT_DIR/happykrishi_backend"
FLUTTER_DIR="$SCRIPT_DIR/happykrishi_flutter"
PORT=3000
PID_FILE="$BACKEND_DIR/app.pid"
LOG_FILE="$BACKEND_DIR/dev.log"
NODE_BIN="node"   # use system node locally (prod server uses /usr/bin/node = Node 22)

log() { echo "[$(date '+%H:%M:%S')] $1"; }

# ── Start backend if not already running on port 3000 ────────────────────────
if lsof -ti tcp:$PORT >/dev/null 2>&1; then
  log "✓ Backend already running on port $PORT"
else
  log "Starting backend on port $PORT..."
  cd "$BACKEND_DIR"
  echo "" >> "$LOG_FILE"
  echo "======== DEV START $(date) ========" >> "$LOG_FILE"
  PORT=$PORT nohup $NODE_BIN app.js >> "$LOG_FILE" 2>&1 &
  echo $! > "$PID_FILE"

  # Wait up to 8s for backend to be ready
  for i in $(seq 1 8); do
    sleep 1
    if lsof -ti tcp:$PORT >/dev/null 2>&1; then
      log "✓ Backend started (PID: $(cat $PID_FILE))"
      break
    fi
    if [ $i -eq 8 ]; then
      log "✗ Backend failed to start. Last logs:"
      tail -20 "$LOG_FILE" | sed 's/^/  /'
      exit 1
    fi
  done
  cd - > /dev/null
fi

log "  Logs: $LOG_FILE"
log ""

# ── Flutter on Chrome — API points to local backend ──────────────────────────
# Uses localhost because Chrome runs on the same machine as the backend.
# For a physical Android device on the same WiFi, replace localhost with your
# Mac's LAN IP (ipconfig getifaddr en0). For Android emulator use 10.0.2.2.
log "Starting Flutter on Chrome..."
cd "$FLUTTER_DIR"
flutter run -d chrome \
  --dart-define=API_BASE_URL="http://localhost:$PORT" \
  --dart-define=WS_BASE_URL="ws://localhost:$PORT/ws"
