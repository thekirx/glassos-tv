# Shared setup for the tools/ scripts. Source it, don't run it.
#
# Which TV: $ANDROID_SERIAL, else the first line of tools/.device (ignored by git), else adb's only device.
# Which app: $GLASS_PKG, default the upstream package. The family build is io.github.abhishekkaisar.glassos.family.
# Results go to tools/out/ (ignored by git: dumps can contain device and profile details).

TOOLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="$TOOLS_DIR/out"
mkdir -p "$OUT_DIR"

if command -v adb >/dev/null 2>&1; then
    ADB_BIN=adb
elif [ -x "${ANDROID_HOME:-$HOME/Library/Android/sdk}/platform-tools/adb" ]; then
    ADB_BIN="${ANDROID_HOME:-$HOME/Library/Android/sdk}/platform-tools/adb"
else
    echo "adb not found (install platform-tools or set ANDROID_HOME)" >&2; exit 1
fi

if [ -z "${ANDROID_SERIAL:-}" ] && [ -f "$TOOLS_DIR/.device" ]; then
    ANDROID_SERIAL="$(head -n1 "$TOOLS_DIR/.device" | tr -d '[:space:]')"
fi
export ANDROID_SERIAL

PKG="${GLASS_PKG:-io.github.abhishekkaisar.glassos}"
# The class keeps the original namespace in every flavor.
ACTIVITY="$PKG/io.github.abhishekkaisar.glassos.MainActivity"
GOOGLE_HOME=com.google.android.apps.tv.launcherx

adb() { "$ADB_BIN" "$@"; }
sh_tv() { "$ADB_BIN" shell "$@" | tr -d '\r'; }

need_device() {
    if ! "$ADB_BIN" get-state >/dev/null 2>&1; then
        echo "No TV reachable over adb (serial: ${ANDROID_SERIAL:-auto})." >&2; exit 1
    fi
}

# The focused window, for example "io.github.abhishekkaisar.glassos/io...MainActivity" or "GlassHome".
focus() { sh_tv dumpsys window | sed -n 's/.*mCurrentFocus=Window{[^ ]* [^ ]* \([^}]*\)}.*/\1/p' | head -n1; }

# Glass is in front: its activity, or its Home overlay window (titled GlassHome).
glass_in_front() {
    local f; f="$(focus)"
    case "$f" in "$PKG/"*|GlassHome) return 0 ;; *) return 1 ;; esac
}

stamp() { date +%Y%m%d-%H%M%S; }
