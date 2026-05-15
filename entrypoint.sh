#!/usr/bin/env bash
set -e

# ── Diagnostic helpers ────────────────────────────────────────────────────────
log() { echo "[entrypoint] $(date -u '+%Y-%m-%dT%H:%M:%SZ') $*"; }

# ── /data inventory ───────────────────────────────────────────────────────────
log "=== /data directory inventory ==="
if [ -d /data ]; then
  log "Total disk usage of /data:"
  du -sh /data 2>&1 || true
  log "Top-level contents of /data:"
  ls -lah /data 2>&1 || true
  log "Full recursive listing of /data (find):"
  find /data -maxdepth 5 -ls 2>&1 || true
else
  log "WARNING: /data does not exist or is not mounted."
fi
log "=== end /data inventory ==="

# ── Hermes config directory inventory ────────────────────────────────────────
log "=== /root/.hermes directory inventory ==="
if [ -d /root/.hermes ]; then
  log "Total disk usage of /root/.hermes:"
  du -sh /root/.hermes 2>&1 || true
  log "Full recursive listing of /root/.hermes:"
  find /root/.hermes -maxdepth 5 -ls 2>&1 || true
  log "config.yaml contents:"
  cat /root/.hermes/config.yaml 2>&1 || true
else
  log "WARNING: /root/.hermes does not exist."
fi
log "=== end /root/.hermes inventory ==="

# ── Auto-update ───────────────────────────────────────────────────────────────
AUTO_UPDATE="${AUTO_UPDATE:-true}"

if [ "$AUTO_UPDATE" = "true" ]; then
  log "Checking for Hermes updates..."
  cd /opt/hermes-agent
  if git pull --recurse-submodules 2>&1 | grep -v 'Already up to date'; then
    log "Updating dependencies..."
    VIRTUAL_ENV=/opt/hermes-agent/venv uv pip install -e ".[all]" --quiet
    log "Update complete."
  else
    log "Already up to date."
  fi
fi

# ── Dashboard startup with error capture ─────────────────────────────────────
DASHBOARD_LOG="/tmp/hermes-dashboard.log"
log "Starting dashboard. Output will be tee'd to $DASHBOARD_LOG and stdout."

hermes dashboard --host 127.0.0.1 --port 9119 --no-open > >(tee -a "$DASHBOARD_LOG") 2>&1 &
DASHBOARD_PID=$!
log "Dashboard process started with PID $DASHBOARD_PID."

# ── Wait for dashboard, logging progress every 5 seconds ─────────────────────
log "Waiting for dashboard to be ready on port 9119..."
ELAPSED=0
TIMEOUT=120
until bash -c 'echo > /dev/tcp/127.0.0.1/9119' 2>/dev/null; do
  sleep 1
  ELAPSED=$((ELAPSED + 1))

  # Log a heartbeat every 5 seconds so we can see progress in Railway logs
  if [ $((ELAPSED % 5)) -eq 0 ]; then
    log "Still waiting... ${ELAPSED}s elapsed."
    log "--- recent dashboard output (last 20 lines) ---"
    tail -n 20 "$DASHBOARD_LOG" 2>/dev/null || true
    log "--- end dashboard output ---"
  fi

  # If the dashboard process has already exited, capture its output and abort
  if ! kill -0 "$DASHBOARD_PID" 2>/dev/null; then
    log "ERROR: Dashboard process (PID $DASHBOARD_PID) exited unexpectedly after ${ELAPSED}s."
    log "=== full dashboard log ==="
    cat "$DASHBOARD_LOG" 2>/dev/null || true
    log "=== end dashboard log ==="
    log "=== Python/system environment ==="
    python --version 2>&1 || true
    hermes --version 2>&1 || true
    log "=== end environment ==="
    exit 1
  fi

  if [ "$ELAPSED" -ge "$TIMEOUT" ]; then
    log "ERROR: Timed out after ${TIMEOUT}s waiting for dashboard on port 9119."
    log "=== full dashboard log ==="
    cat "$DASHBOARD_LOG" 2>/dev/null || true
    log "=== end dashboard log ==="
    kill "$DASHBOARD_PID" 2>/dev/null || true
    exit 1
  fi
done

log "Dashboard is ready after ${ELAPSED}s."

# ── Auth proxy ────────────────────────────────────────────────────────────────
exec python /auth_proxy.py
