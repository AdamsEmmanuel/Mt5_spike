FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive \
    WINEPREFIX=/opt/wineprefix \
    WINEARCH=win64 \
    WINEDEBUG=-all \
    WINEDLLOVERRIDES="mscoree,mshtml=" \
    DISPLAY=:99

# Pinned Windows Python used to run the MetaTrader5 package under Wine.
ARG PY_WIN_URL=https://www.python.org/ftp/python/3.11.9/python-3.11.9-amd64.exe

RUN apt-get update && apt-get install -y --no-install-recommends \
        wine64 xvfb xauth wget ca-certificates cabextract python3 procps \
    && rm -rf /var/lib/apt/lists/*

RUN wget -q -O /opt/python-win.exe "$PY_WIN_URL"

# Headway MT5 setup .exe must be placed in installer/ before building.
COPY installer/ /opt/installer/
COPY scripts/build_wine.sh /opt/build_wine.sh
RUN bash /opt/build_wine.sh && rm -f /opt/python-win.exe

COPY scripts/ /opt/spike/
RUN chmod +x /opt/spike/*.sh /opt/build_wine.sh

CMD ["/opt/spike/start.sh"]
