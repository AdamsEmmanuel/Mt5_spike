#!/bin/bash
# Container entrypoint. Starts the report server first so Render's health check passes.
set -uo pipefail
export WINEPREFIX=/opt/wineprefix WINEARCH=win64 WINEDEBUG=-all \
       WINEDLLOVERRIDES="mscoree,mshtml=" DISPLAY=:99
export PORT="${PORT:-8080}"
mkdir -p /tmp/spike

echo "== virtual display"
Xvfb :99 -screen 0 1024x768x16 -nolisten tcp >/tmp/spike/xvfb.log 2>&1 &
sleep 2

echo "== report server on port $PORT"
python3 /opt/spike/report_server.py >/tmp/spike/server.log 2>&1 &

echo "== memory sampler"
/opt/spike/mem_report.sh &

TERM_UNIX="$(find "$WINEPREFIX/drive_c" -iname terminal64.exe | head -1)"
if [ -z "$TERM_UNIX" ]; then
  echo "terminal64.exe not found; image is missing MT5" | tee /tmp/spike/login.out
else
  REL="${TERM_UNIX#$WINEPREFIX/drive_c/}"
  export MT5_PATH="C:\\$(echo "$REL" | tr '/' '\\')"
  echo "== login check (terminal: $MT5_PATH)"
  timeout 300 wine 'C:\Python311\python.exe' -u 'Z:\opt\spike\check_login.py' \
    >/tmp/spike/login.out 2>&1
  echo "login check exit code: $?" | tee -a /tmp/spike/login.out
fi

echo "== spike running; keep container alive and sample memory"
wait
