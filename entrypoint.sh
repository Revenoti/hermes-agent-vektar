#!/usr/bin/env bash
set -e

AUTO_UPDATE="${AUTO_UPDATE:-true}"

if [ "$AUTO_UPDATE" = "true" ]; then
  echo "Checking for Hermes updates..."
  cd /opt/hermes-agent
  if git pull --recurse-submodules 2>&1 | grep -v 'Already up to date'; then
    echo "Updating dependencies..."
    VIRTUAL_ENV=/opt/hermes-agent/venv uv pip install -e ".[all]" --quiet
    echo "Update complete."
  else
    echo "Already up to date."
  fi
fi

hermes dashboard --host 127.0.0.1 --port 9119 --no-open &

echo "Waiting for dashboard to be ready on port 9119..."
until bash -c 'echo > /dev/tcp/127.0.0.1/9119' 2>/dev/null; do
  sleep 0.5
done
echo "Dashboard is ready."

exec python /auth_proxy.py
