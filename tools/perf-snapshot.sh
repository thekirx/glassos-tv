#!/usr/bin/env bash
# One performance snapshot of Glass on the TV: memory on the home screen, D-pad frame timing, memory with another
# app in front, and cold start time. Appends one row to tools/out/perf.csv and keeps raw dumps in tools/out/<time>/.
#
#   tools/perf-snapshot.sh [LABEL]
#
# Env: KEYS (D-pad presses, default 200), BG_WAIT_S (default 60), COLD=0 to skip the
# cold start (it force-stops Glass, so the stock home shows for a moment), GLASS_PKG, ANDROID_SERIAL.
# The background app is the TV's Settings: it plays nothing (a streaming app may resume a video on its own).
set -euo pipefail
source "$(dirname "$0")/lib.sh"
need_device

LABEL="${1:-snapshot}"; KEYS="${KEYS:-200}"
BG_WAIT_S="${BG_WAIT_S:-60}"; COLD="${COLD:-1}"
RUN="$OUT_DIR/$(stamp)-$LABEL"; mkdir -p "$RUN"
CSV="$OUT_DIR/perf.csv"
[ -f "$CSV" ] || echo "time,label,pkg,version,pss_home_kb,graphics_home_kb,java_home_kb,native_home_kb,frames,janky,janky_pct,p50_ms,p90_ms,p95_ms,p99_ms,pss_bg_kb,cold_start_ms,mem_available_kb" > "$CSV"

pss() { awk '/TOTAL PSS:/{print $3; exit} /^ *TOTAL +[0-9]/{print $2; exit}' "$1"; }
row() { awk -F: -v k="$2" '$1 ~ "^ *"k"$" {split($2, v, " "); print v[1]; exit}' "$1"; }
gfx() { grep -m1 "$2" "$1" | sed 's/.*: *//; s/ms//; s/ *(.*//' | tr -d ' '; }

version="$(sh_tv dumpsys package "$PKG" | sed -n 's/.*versionName=//p' | head -n1)"
echo "Glass $PKG $version, label '$LABEL'"

# 1. Home screen, settled.
sh_tv am start -n "$ACTIVITY" >/dev/null; sleep 8
sh_tv dumpsys meminfo "$PKG" > "$RUN/meminfo-home.txt"
pss_home=$(pss "$RUN/meminfo-home.txt"); gfx_home=$(row "$RUN/meminfo-home.txt" Graphics)
java_home=$(row "$RUN/meminfo-home.txt" "Java Heap"); native_home=$(row "$RUN/meminfo-home.txt" "Native Heap")
echo "  home: PSS ${pss_home} kB (graphics ${gfx_home}, java ${java_home}, native ${native_home})"

# 2. D-pad run: along the dock and down into the rows and back, about 6 presses a second.
sh_tv dumpsys gfxinfo "$PKG" reset >/dev/null
# Built here and sent as one line: a multi-line script over `adb shell` silently does nothing.
pattern=(22 22 22 22 22 21 21 21 21 21 20 20 22 22 22 21 21 21 19 19)
keys=""; for i in $(seq 0 $((KEYS - 1))); do keys="$keys ${pattern[$((i % 20))]}"; done
sh_tv "for k in$keys; do input keyevent \$k; sleep 0.05; done"
sh_tv dumpsys gfxinfo "$PKG" > "$RUN/gfxinfo.txt"
frames=$(gfx "$RUN/gfxinfo.txt" "Total frames rendered"); janky=$(grep -m1 "Janky frames:" "$RUN/gfxinfo.txt" | awk '{print $3}')
janky_pct=$(grep -m1 "Janky frames:" "$RUN/gfxinfo.txt" | sed 's/.*(\(.*\)%).*/\1/')
p50=$(gfx "$RUN/gfxinfo.txt" "50th percentile"); p90=$(gfx "$RUN/gfxinfo.txt" "90th percentile")
p95=$(gfx "$RUN/gfxinfo.txt" "95th percentile"); p99=$(gfx "$RUN/gfxinfo.txt" "99th percentile")
echo "  d-pad: $frames frames, $janky janky ($janky_pct%), p50 ${p50} ms, p90 ${p90} ms, p99 ${p99} ms"

# 3. Another app in front for a while.
sh_tv am start -a android.settings.SETTINGS >/dev/null 2>&1 || true
echo "  Settings in front, waiting ${BG_WAIT_S}s"; sleep "$BG_WAIT_S"
sh_tv dumpsys meminfo "$PKG" > "$RUN/meminfo-bg.txt"
pss_bg=$(pss "$RUN/meminfo-bg.txt"); echo "  background: PSS ${pss_bg:-not running} kB"
sh_tv cat /proc/meminfo > "$RUN/proc-meminfo.txt"
mem_avail=$(awk '/MemAvailable/{print $2}' "$RUN/proc-meminfo.txt")
sh_tv dumpsys meminfo "$GOOGLE_HOME" > "$RUN/meminfo-google-home.txt" 2>/dev/null || true

# 4. Cold start (force-stop, then start and wait for the first frame).
cold=""
if [ "$COLD" = 1 ]; then
    sh_tv am force-stop "$PKG"; sleep 2
    sh_tv am start -W -n "$ACTIVITY" > "$RUN/cold-start.txt"
    cold=$(awk '/TotalTime/{print $2}' "$RUN/cold-start.txt")
    echo "  cold start: ${cold} ms"
    sleep 3
fi
sh_tv am start -n "$ACTIVITY" >/dev/null 2>&1 || true

echo "$(stamp),$LABEL,$PKG,$version,$pss_home,$gfx_home,$java_home,$native_home,$frames,$janky,$janky_pct,$p50,$p90,$p95,$p99,${pss_bg:-},${cold:-},$mem_avail" >> "$CSV"
echo "Saved: $CSV and $RUN/"
