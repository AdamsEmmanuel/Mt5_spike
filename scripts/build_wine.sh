#!/bin/bash
# Runs during `docker build`. Each stage checks its own result, so a failure
# stops the build with a clear message instead of a silent broken image.
set -euo pipefail
export WINEPREFIX=/opt/wineprefix WINEARCH=win64 WINEDEBUG=-all \
       WINEDLLOVERRIDES="mscoree,mshtml=" DISPLAY=:99

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
wine64 wineboot -i >/dev/null 2>&1 || true
wineserver -w

echo "== 2. install Windows Python 3.11"
timeout 900 wine64 /opt/python-win.exe /quiet InstallAllUsers=1 Include_test=0 Include_launcher=0 || true
wineserver -w
PY_UNIX="$WINEPREFIX/drive_c/Program Files/Python311/python.exe"
if [ ! -f "$PY_UNIX" ]; then
  echo "ERROR: Windows Python did not install at $PY_UNIX"
  exit 1
fi
PY_WIN='C:\Program Files\Python311\python.exe'

echo "== 3. install MetaTrader5 package into Windows Python"
timeout 900 wine64 "$PY_WIN" -m pip install --no-cache-dir MetaTrader5 || true
wineserver -w
timeout 300 wine64 "$PY_WIN" -c "import MetaTrader5; print('MetaTrader5 import ok', MetaTrader5.__file__)" \
  || { echo "ERROR: MetaTrader5 package did not import under Wine"; exit 1; }

echo "== 4. install Headway MT5 terminal (silent)"
timeout 900 wine64 "${INSTALLERS[0]}" /S || true
wineserver -w
TERM_UNIX="$(find "$WINEPREFIX/drive_c" -iname terminal64.exe | head -1)"
if [ -z "$TERM_UNIX" ]; then
  echo "ERROR: terminal64.exe not found after install. The installer may not support /S;"
  echo "       check the installer's silent switch and update this line."
  exit 1
fi
echo "terminal installed at: $TERM_UNIX"
echo "== build stages complete"
