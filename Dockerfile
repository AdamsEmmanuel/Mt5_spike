FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive \
    WINEPREFIX=/opt/wineprefix \
    WINEARCH=win64 \
    WINEDEBUG=-all \
    WINEDLLOVERRIDES="mscoree,mshtml=" \
    DISPLAY=:99

# Official embeddable Python 3.11 zip: a plain archive, no installer needed.
ARG PY_WIN_URL=https://www.python.org/ftp/python/3.11.9/python-3.11.9-embed-amd64.zip

# xwininfo lists open windows and xdotool sends key presses, so installer dialogs
# under the virtual display can be seen and answered.
RUN apt-get update && apt-get install -y --no-install-recommends \
        wine wine64 xvfb xauth wget ca-certificates cabextract python3 procps \
        x11-utils xdotool \
    && rm -rf /var/lib/apt/lists/* \
    && for t in wine wineserver Xvfb python3 wget ps find xwininfo xdotool; do \
         command -v "$t" >/dev/null || { echo "MISSING TOOL: $t"; exit 1; }; \
       done

RUN wget -q -O /opt/python-embed.zip "$PY_WIN_URL"

# Headway MT5 setup .exe must be placed in installer/ before building.
COPY installer/ /opt/installer/
COPY scripts/build_wine.sh /opt/build_wine.sh
RUN bash /opt/build_wine.sh && rm -f /opt/python-embed.zip

COPY scripts/ /opt/spike/
RUN chmod +x /opt/spike/*.sh /opt/build_wine.sh

CMD ["/opt/spike/start.sh"]
