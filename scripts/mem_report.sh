#!/bin/bash
# Samples container memory and the largest processes every 60 seconds.
# Output: /tmp/spike/mem.log (one line per sample).
LOG=/tmp/spike/mem.log
mkdir -p /tmp/spike
while true; do
  ts=$(date -u +%FT%TZ)
  if [ -f /sys/fs/cgroup/memory.current ]; then           # cgroup v2
    used=$(cat /sys/fs/cgroup/memory.current)
    limit=$(cat /sys/fs/cgroup/memory.max 2>/dev/null)
  else                                                     # cgroup v1
    used=$(cat /sys/fs/cgroup/memory/memory.usage_in_bytes 2>/dev/null)
    limit=$(cat /sys/fs/cgroup/memory/memory.limit_in_bytes 2>/dev/null)
  fi
  top=$(ps -eo rss,comm --sort=-rss | sed -n '2,6p' | awk '{printf "%s:%s ", $2, $1}')
  echo "$ts used_mb=$(( ${used:-0} / 1048576 )) limit=${limit:-unknown} top_rss_kb=[$top]" >> "$LOG"
  sleep 60
done
