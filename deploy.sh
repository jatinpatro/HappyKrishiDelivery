#!/bin/bash
set -e

##################################
# SETTINGS
##################################

PEM_KEY="/Users/I503151/Desktop/HappyKrishi/HappyKrishiBackend/HAPPYKRISHI/CUSTOMERONBOARDING/happykrishi.pem"
REMOTE_USER="root"
REMOTE_HOST="88.222.212.244"

BACKEND_DIR="/root/HAPPYKRISHI_DELIVERY"
WEB_DIR="/root/HAPPYKRISHI_DELIVERY_WEB"
API_PORT="4000"
API_BASE_URL="http://${REMOTE_HOST}:${API_PORT}"
WEB_PATH="/hkdelivery"

FLUTTER_DIR="$(dirname "$0")/happykrishi_flutter"
BACKEND_SRC="$(dirname "$0")/happykrishi_backend"

# Local DB backup directory
LOCAL_DB_BACKUP_DIR="$(dirname "$0")/db_backups"

SSH_OPTS="-i ${PEM_KEY} -o StrictHostKeyChecking=no"
NODE_BIN="/usr/bin/node"   # Node 22 LTS — node 24 breaks better-sqlite3

##################################
# HELPERS
##################################
log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"; }
fail() { echo "❌ $1"; exit 1; }

##################################
# PRECHECKS
##################################
log "Starting HappyKrishi Delivery deployment..."
[ -f "$PEM_KEY" ] || fail "PEM key not found: $PEM_KEY"
chmod 400 "$PEM_KEY"
command -v rsync  >/dev/null || fail "rsync not installed"
command -v flutter >/dev/null || fail "flutter not installed"
mkdir -p "$LOCAL_DB_BACKUP_DIR"
log "✓ Prerequisites OK"

##################################
# STEP 1: DOWNLOAD DB BACKUP TO LOCAL
##################################
log "Downloading DB backup from server to local..."
BACKUP_TS=$(date '+%Y%m%d_%H%M%S')
LOCAL_BACKUP="${LOCAL_DB_BACKUP_DIR}/happykrishi_${BACKUP_TS}.db"

# Check if DB exists on server, then download it
DB_EXISTS=$(ssh $SSH_OPTS ${REMOTE_USER}@${REMOTE_HOST} \
  "[ -f ${BACKEND_DIR}/data/happykrishi.db ] && echo yes || echo no")

if [ "$DB_EXISTS" = "yes" ]; then
  rsync -az -e "ssh ${SSH_OPTS}" \
    ${REMOTE_USER}@${REMOTE_HOST}:${BACKEND_DIR}/data/happykrishi.db \
    "$LOCAL_BACKUP"
  log "✅ DB backed up locally → $LOCAL_BACKUP"
  log "   Size: $(du -h "$LOCAL_BACKUP" | cut -f1)"
else
  log "ℹ️  No DB on server yet (fresh deploy) — skipping download"
fi

##################################
# BUILD FLUTTER WEB
##################################
log "Building Flutter web (API: ${API_BASE_URL})..."
cd "$FLUTTER_DIR"
flutter build web \
  --release \
  --dart-define=API_BASE_URL="${API_BASE_URL}" \
  --dart-define=WS_BASE_URL="ws://${REMOTE_HOST}:${API_PORT}" \
  --base-href="${WEB_PATH}/"
log "✓ Flutter web built"

##################################
# BUILD FLUTTER APK
##################################
log "Building Flutter APK (API: ${API_BASE_URL})..."
flutter build apk \
  --release \
  --dart-define=API_BASE_URL="${API_BASE_URL}" \
  --dart-define=WS_BASE_URL="ws://${REMOTE_HOST}:${API_PORT}"
log "✓ APK built: build/app/outputs/flutter-apk/app-release.apk"
cd - > /dev/null

##################################
# PREPARE SERVER DIRECTORIES
##################################
log "Preparing remote server..."
ssh $SSH_OPTS ${REMOTE_USER}@${REMOTE_HOST} "
  mkdir -p ${BACKEND_DIR}/logs ${BACKEND_DIR}/data ${WEB_DIR}
  echo '[Server] Directories ready'
"
log "✓ Server prepared"

##################################
# SYNC BACKEND (never touches data/)
##################################
log "Syncing backend..."
rsync -az --delete \
  --exclude node_modules \
  --exclude logs \
  --exclude '*.pid' \
  --exclude 'data/' \
  -e "ssh ${SSH_OPTS}" \
  "${BACKEND_SRC}/" \
  ${REMOTE_USER}@${REMOTE_HOST}:${BACKEND_DIR}/
log "✓ Backend synced"

##################################
# SYNC FLUTTER WEB
##################################
log "Syncing Flutter web..."
rsync -az --delete \
  -e "ssh ${SSH_OPTS}" \
  "${FLUTTER_DIR}/build/web/" \
  ${REMOTE_USER}@${REMOTE_HOST}:${WEB_DIR}/
log "✓ Flutter web synced"

##################################
# SYNC APK
##################################
log "Syncing APK..."
rsync -az \
  -e "ssh ${SSH_OPTS}" \
  "${FLUTTER_DIR}/build/app/outputs/flutter-apk/app-release.apk" \
  ${REMOTE_USER}@${REMOTE_HOST}:${WEB_DIR}/happykrishi-delivery.apk
log "✓ APK synced"

##################################
# INSTALL DEPS + START BACKEND
##################################
log "Installing dependencies and starting backend..."

ssh $SSH_OPTS ${REMOTE_USER}@${REMOTE_HOST} << ENDSSH
set -e

cd ${BACKEND_DIR}
NODE22="${NODE_BIN}"

echo "[Server] Node versions:"
echo "  default: \$(node --version)"
echo "  node22:  \$(\$NODE22 --version)"

# ── Install app deps (excluding better-sqlite3) ───────────────────────────────
echo "[Server] Installing npm dependencies..."
PATH=\$(dirname \$NODE22):\$PATH npm install --production 2>&1 | tail -3
echo "[Server] ✓ npm deps installed"

# ── Ensure better-sqlite3 is globally installed with Node 22 ──────────────────
# Global install is independent of project node_modules — npm install never removes it
echo "[Server] Checking global better-sqlite3..."
if ! \$NODE22 -e "require('/root/.npm-global/lib/node_modules/better-sqlite3')" 2>/dev/null; then
  echo "[Server] Installing better-sqlite3 globally with Node 22..."
  PATH=\$(dirname \$NODE22):\$PATH npm install -g better-sqlite3 2>&1 | tail -3
  echo "[Server] ✓ better-sqlite3 globally installed"
else
  echo "[Server] ✓ better-sqlite3 global install OK"
fi

# ── Write autostart script (always uses Node 22) ─────────────────────────────
cat > autostart.sh << 'EOT'
#!/bin/bash

APP_DIR="/root/HAPPYKRISHI_DELIVERY"
LOG_FILE="\$APP_DIR/logs/app.log"
PID_FILE="\$APP_DIR/app.pid"
NODE_BIN="/usr/bin/node"
PORT=4000

echo "[Autostart \$(date)] Script triggered" >> \$LOG_FILE
cd \$APP_DIR || { echo "[Autostart \$(date)] ERROR: Cannot cd to \$APP_DIR" >> \$LOG_FILE; exit 1; }

if [ -f \$PID_FILE ]; then
  OLD_PID=\$(cat \$PID_FILE)
  if kill -0 \$OLD_PID 2>/dev/null; then
    echo "[Autostart \$(date)] App already running (PID: \$OLD_PID)" >> \$LOG_FILE
    exit 0
  else
    rm -f \$PID_FILE
  fi
fi

echo "[Autostart \$(date)] Starting on port \$PORT with \$(\$NODE_BIN --version)..." >> \$LOG_FILE
PORT=\$PORT nohup \$NODE_BIN app.js >> \$LOG_FILE 2>&1 &
NEW_PID=\$!
echo \$NEW_PID > \$PID_FILE

sleep 2
if kill -0 \$NEW_PID 2>/dev/null; then
  echo "[Autostart \$(date)] ✓ Started PID: \$NEW_PID" >> \$LOG_FILE
else
  echo "[Autostart \$(date)] ✗ Failed to start!" >> \$LOG_FILE
  rm -f \$PID_FILE
  exit 1
fi
EOT
chmod +x autostart.sh
echo "[Server] ✓ Autostart script updated"

# ── Configure cron ────────────────────────────────────────────────────────────
CRON_LINE="* * * * * ${BACKEND_DIR}/autostart.sh"
(crontab -l 2>/dev/null | grep -v "${BACKEND_DIR}/autostart.sh" || true; echo "\$CRON_LINE") | crontab -
echo "[Server] ✓ Cron configured"

# ── Stop old process ──────────────────────────────────────────────────────────
if [ -f app.pid ]; then
  OLD_PID=\$(cat app.pid)
  if kill -0 \$OLD_PID 2>/dev/null; then
    echo "[Server] Stopping old process \$OLD_PID..."
    kill \$OLD_PID; sleep 3
    kill -9 \$OLD_PID 2>/dev/null || true
  fi
  rm -f app.pid
fi
fuser -k 4000/tcp 2>/dev/null || true
sleep 1

# ── Start fresh ───────────────────────────────────────────────────────────────
echo "" >> logs/app.log
echo "======== DEPLOYMENT \$(date) ========" >> logs/app.log
./autostart.sh

sleep 4
if [ -f app.pid ] && kill -0 \$(cat app.pid) 2>/dev/null; then
  echo "[Server] ✅ Backend running on port 4000 (PID: \$(cat app.pid))"
  echo "[Server] Recent logs:"
  tail -15 logs/app.log | sed 's/^/  /'
else
  echo "[Server] ✗ Backend failed to start!"
  tail -30 logs/app.log | sed 's/^/  /'
  exit 1
fi
ENDSSH

log "✓ Backend deployed and running"

##################################
# CONFIGURE NGINX (once only)
##################################
log "Configuring nginx..."
ssh $SSH_OPTS ${REMOTE_USER}@${REMOTE_HOST} <<'ENDSSH'
set -e
if ! grep -q "/hkdelivery" /etc/nginx/sites-enabled/default; then
  echo "[Server] Adding /hkdelivery to nginx..."
  python3 - <<'PYEOF'
with open('/etc/nginx/sites-enabled/default', 'r') as f:
    content = f.read()
new_locations = """
    location /hkdelivery {
        alias /root/HAPPYKRISHI_DELIVERY_WEB;
        try_files $uri $uri/ /hkdelivery/index.html;
        index index.html;
    }
    location /hkdelivery-api/ {
        proxy_pass http://127.0.0.1:4000/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_cache_bypass $http_upgrade;
    }
"""
lines = content.split('\n')
for i in range(len(lines)-1, -1, -1):
    if lines[i].strip() == '}':
        lines.insert(i, new_locations)
        break
with open('/etc/nginx/sites-enabled/default', 'w') as f:
    f.write('\n'.join(lines))
print("nginx config updated")
PYEOF
fi
# Always ensure /root is executable by nginx
chmod o+x /root
chmod -R o+rX /root/HAPPYKRISHI_DELIVERY_WEB
nginx -t && systemctl reload nginx
echo "[Server] ✓ nginx configured and reloaded"
ENDSSH
log "✓ nginx configured"

##################################
# DONE
##################################
log ""
log "════════════════════════════════════════════════"
log "✅  DEPLOYMENT COMPLETE"
log "════════════════════════════════════════════════"
log ""
log "  🌐  Web App:    http://${REMOTE_HOST}${WEB_PATH}/"
log "  📱  APK:        http://${REMOTE_HOST}${WEB_PATH}/happykrishi-delivery.apk"
log "  🔌  Backend:    http://${REMOTE_HOST}:${API_PORT}"
log ""
log "  Local DB backups: ${LOCAL_DB_BACKUP_DIR}/"
log "  Latest backup:    ${LOCAL_BACKUP:-none}"
log ""
log "  Monitor: ssh -i ${PEM_KEY} ${REMOTE_USER}@${REMOTE_HOST} 'tail -f ${BACKEND_DIR}/logs/app.log'"
log "════════════════════════════════════════════════"
