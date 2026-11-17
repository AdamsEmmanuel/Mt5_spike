#!/bin/bash
# Runs during `docker build`. Stages 1-3 stop on any error. Stage 4 is a diagnostic
# loop: it must not stop on empty results, so `set -e` is turned off there.
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

echo "== 4. install Headway MT5 terminal (diagnostic run, up to 10 min)"
set +e                                   # diagnostic loop: empty results are data, not errors
INST="${INSTALLERS[0]}"
echo "installer: $(basename "$INST") size=$(stat -c %s "$INST") bytes"
echo "first two bytes (MZ expected): $(head -c 2 "$INST")"

wine "$INST" /S >/tmp/installer.out 2>&1 &
IPID=$!
FOUND=""
WINDOWS=""
for ((m = 1; m <= 10; m++)); do
  sleep 60
  WINDOWS="$(xwininfo -root -children 2>/dev/null \
    | sed -n 's/^ *0x[0-9a-f]* "\([^"]*\)".*/\1/p' | grep -v '^$' | sort -u | tr '\n' '|')"
  FOUND="$(find "$WINEPREFIX/drive_c" -iname terminal64.exe 2>/dev/null | head -1)"
  FILES="$(find "$WINEPREFIX/drive_c" -type f 2>/dev/null | wc -l)"
  ALIVE="$(kill -0 $IPID 2>/dev/null && echo yes || echo no)"
  # CPU time of Wine processes: if it keeps rising, the installer is working.
  CPU="$(ps -eo pid,time,comm 2>/dev/null | grep -iE 'wine|mt5|setup' | head -4 | tr -s ' ' | tr '\n' ';')"
  echo "  t+${m}min running=$ALIVE files=$FILES windows=[$WINDOWS] cpu=[$CPU] terminal=${FOUND:+yes}"
  [ -n "$FOUND" ] && break
  [ "$ALIVE" = "no" ] && break
  # Press Enter on installer windows (lowercase mt5setup is the title we actually see).
  for w in $(xdotool search --name 'mt5setup|[Ss]etup|[Ii]nstall|MetaTrader|Headway' 2>/dev/null | head -5); do
    xdotool windowactivate --sync "$w" 2>/dev/null
    xdotool key --window "$w" Return 2>/dev/null
    xdotool key Return 2>/dev/null
  done
done
set -e

if [ -z "$FOUND" ]; then
  echo "ERROR: terminal64.exe not found after diagnostic run."
  echo "installer still running: $(kill -0 $IPID 2>/dev/null && echo yes || echo no)"
  echo "--- last open windows: $WINDOWS"
  echo "--- installer output:"
  tail -20 /tmp/installer.out 2>/dev/null || true
  echo "--- most recently changed files:"
  find "$WINEPREFIX/drive_c" -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -10 | cut -d' ' -f2-
  exit 1
fi

sleep 30
wineserver -w || true
echo "terminal installed at: $FOUND"
echo "== build stages complete"
