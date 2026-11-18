#!/bin/bash
# Runs during `docker build`. Stages 1-3 stop on any error.
# Stage 4 is a probe: it opens the Headway installer, presses Enter on its window
# every 5 seconds for up to 5 minutes, and logs every window title it sees.
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

echo "== 4. probe: open installer, press Enter every 5s, log windows"
INST="${INSTALLERS[0]}"
echo "installer: $(basename "$INST") size=$(stat -c %s "$INST") bytes"
wine "$INST" /S >/tmp/installer.out 2>&1 &
IPID=$!
sleep 5

for step in $(seq 1 60); do
  sleep 5
  RUNNING=$(kill -0 $IPID 2>/dev/null && echo yes || echo no)
  FILES=$(find "$WINEPREFIX/drive_c" -type f | wc -l)
  WINDOWS=$(xwininfo -root -children 2>/dev/null \
    | sed -n 's/^ *0x[0-9a-f]* "\([^"]*\)".*/\1/p' | grep -v '^$' | sort -u | tr '\n' '|')
  PRESSED=no
  for w in $(xdotool search --name 'headway|Headway|setup|Setup|install|Install|license|License|MetaTrader' 2>/dev/null | head -5); do
    xdotool windowactivate --sync "$w" 2>/dev/null || true
    sleep 1
    xdotool key --clearmodifiers Return 2>/dev/null || true
    PRESSED=yes
  done
  echo "  t+$((step*5))s running=$RUNNING files=$FILES enter_sent=$PRESSED windows=[$WINDOWS]"
  [ "$RUNNING" = "no" ] && break
done

kill $IPID 2>/dev/null || true
echo "--- installer output (up to 30 lines):"
tail -30 /tmp/installer.out 2>/dev/null || true
echo "--- end of probe: terminal not installed in this build"
exit 1
