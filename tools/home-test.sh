#!/usr/bin/env bash
# Presses Home on the TV over adb and counts how often Glass ends up in front.
#
#   tools/home-test.sh single [N]            Home once, N times (default 20)
#   tools/home-test.sh double [N] [GAP_MS]   Home twice, GAP_MS apart (default 300), N times
#   tools/home-test.sh app [N] [APP_PKG]     open an app (default YouTube), wait, then Home, N times
#
# Glass counts as in front when its activity or its Home overlay has focus, checked at 2 s and again at 6 s
# after the last press (the second check catches Glass appearing and then losing to the stock home).
# Env: PAUSE_S (seconds between rounds, default 3), GLASS_PKG, ANDROID_SERIAL. Appends to tools/out/home-test.csv.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
need_device

MODE="${1:-single}"; N="${2:-20}"; PAUSE_S="${PAUSE_S:-3}"
case "$MODE" in
    single) ;;
    double) GAP_MS="${3:-300}" ;;
    app) APP="${3:-com.google.android.youtube.tv}" ;;
    *) sed -n '2,12p' "$0"; exit 2 ;;
esac

CSV="$OUT_DIR/home-test.csv"
[ -f "$CSV" ] || echo "time,pkg,mode,param,round,pass,focus_2s,focus_6s" > "$CSV"
param="${GAP_MS:-${APP:-}}"
pass=0

# Start from Glass so every round begins the same way.
sh_tv am start -n "$ACTIVITY" >/dev/null 2>&1 || true
sleep 3

for i in $(seq 1 "$N"); do
    case "$MODE" in
        single) sh_tv input keyevent KEYCODE_HOME ;;
        double)
            # One shell on the TV, so the gap is not stretched by the network round trip.
            gap_s=$(awk "BEGIN{printf \"%.3f\", $GAP_MS/1000}")
            sh_tv "input keyevent KEYCODE_HOME; sleep $gap_s; input keyevent KEYCODE_HOME" ;;
        app)
            sh_tv monkey -p "$APP" -c android.intent.category.LEANBACK_LAUNCHER 1 >/dev/null 2>&1 || true
            sleep 5
            sh_tv input keyevent KEYCODE_HOME ;;
    esac
    sleep 2; f2="$(focus)"
    sleep 4; f6="$(focus)"
    ok=0
    case "$f2" in "$PKG/"*|GlassHome) case "$f6" in "$PKG/"*|GlassHome) ok=1 ;; esac ;; esac
    pass=$((pass + ok))
    printf '%s round %d/%d: %s  (2s: %s | 6s: %s)\n' "$MODE" "$i" "$N" "$([ $ok = 1 ] && echo PASS || echo FAIL)" "$f2" "$f6"
    echo "$(stamp),$PKG,$MODE,$param,$i,$ok,\"$f2\",\"$f6\"" >> "$CSV"
    sleep "$PAUSE_S"
done

echo "RESULT $MODE ${param:+($param) }: $pass / $N ended on Glass"
