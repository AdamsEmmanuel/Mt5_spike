#!/bin/bash
# Runs during `docker build`. Stages 1-3 stop on any error.
# Stage 4 is a probe: it records what the Headway installer tries to download.
set -euo pipefail
export WINEPREFIX=/opt/wineprefix WINEARCH=win64 WINEDEBUG=-all \
       WINEDLLOVERRIDES="mscoree,mshtml=" DISPLAY=:99
PY_DIR="$WINEPREFIX/drive_c/Python311"
PY_WIN='C:\Python311\python.exe'

for tool in wine wineserver Xvfb python3 wget xwininfo xdotool; do
  command -v "$tool" >/dev/null || { echo "ERROR: $tool not on PATH"; exit 1; }
done

shopt -s nullglob
INSTALLERS=(/opt/installer/*.exe)
if [ ${#INSTALLERS[@]} -eq 0 ]; then
  echo "ERROR: no .exe found in installer/. Put the Headway MT5 setup file there and rebuild."
  exit 1
fi

Xvfb :99 -screen 0 1024x768x16 -nolisten tcp >/dev/null 2>&1 &
XPID=$!
trap 'kill $XPID 2>/dev/null || true' EXIT
sleep 2

echo "== 1. init Wine prefix"
wine wineboot -i >/dev/null 2>&1 || true
wineserver -w

echo "== 2. unpack embeddable Python 3.11 to C:\\Python311"
mkdir -p "$PY_DIR"
python3 -m zipfile -e /opt/python-embed.zip "$PY_DIR"
[ -f "$PY_DIR/python.exe" ] || { echo "ERROR: python.exe missing after unzip"; exit 1; }
sed -i 's/^#import site/import site/' "$PY_DIR/python311._pth"
grep -q '^import site' "$PY_DIR/python311._pth" || { echo "ERROR: could not enable site"; exit 1; }
echo "python.exe unpacked and site enabled"

echo "== 3. install pip, then MetaTrader5 with numpy pinned for Wine 8"
wget -q -O "$PY_DIR/get-pip.py" https://bootstrap.pypa.io/get-pip.py
timeout 600 wine "$PY_WIN" 'C:\Python311\get-pip.py' --no-warn-script-location || true
wineserver -w
timeout 120 wine "$PY_WIN" -m pip --version || { echo "ERROR: pip not working under Wine"; exit 1; }
timeout 900 wine "$PY_WIN" -m pip install --no-cache-dir --no-warn-script-location \
  "numpy==1.26.4" MetaTrader5 || true
wineserver -w
timeout 90 wine "$PY_WIN" -c "import MetaTrader5; print('MetaTrader5 import ok')" \
  || { echo "ERROR: MetaTrader5 did not import under Wine"; exit 1; }

echo "== 4. probe: what does the Headway installer try to download?"
INST="${INSTALLERS[0]}"
echo "installer: $(basename "$INST") size=$(stat -c %s "$INST") bytes"
export WINEDEBUG=+winhttp,+wininet,err+all
wine "$INST" /S >/tmp/installer.out 2>&1 &
IPID=$!
for m in 1 2 3 4 5; do
  sleep 60
  RUNNING=$(kill -0 $IPID 2>/dev/null && echo yes || echo no)
  FILES=$(find "$WINEPREFIX/drive_c" -type f | wc -l)
  echo "  t+${m}min running=$RUNNING files=$FILES"
done
kill $IPID 2>/dev/null || true
echo "--- web addresses seen by Wine networking (up to 30):"
grep -aoE 'https?://[^ "\\)>]+' /tmp/installer.out | sort -u | head -30 || true
echo "--- installer log lines mentioning http or download (up to 20):"
grep -aiE 'http|download' /tmp/installer.out | head -20 || true
echo "--- end of probe: terminal not installed in this build"
exit 1
