#!/usr/bin/env bash
# Shows and undoes launcher changes made while testing. Every action asks before it runs.
#
#   tools/rollback.sh status          (default) what Home opens, which launchers are enabled, which watchers run
#   tools/rollback.sh google-home     re-enable the Google TV home and setup apps, drop any Home role given to Glass
#                                     (do this before a factory reset or a system update)
#   tools/rollback.sh official        re-enable the official GlassOS app
#   tools/rollback.sh restore-debloat re-enable every app recorded in tools/out/debloat-done.txt
#   tools/rollback.sh remove-family   uninstall the family build (removes its device admin first)
set -euo pipefail
source "$(dirname "$0")/lib.sh"
need_device

OFFICIAL=io.github.abhishekkaisar.glassos
FAMILY=io.github.abhishekkaisar.glassos.family
SETUP=com.google.android.tungsten.setupwraith

confirm() {
    echo "About to run on the TV:"; printf '  adb shell %s\n' "$@"
    read -r -p "Go ahead? [y/N] " a; [ "$a" = y ] || [ "$a" = Y ]
}
enabled() { sh_tv pm list packages -e "$1" | grep -qx "package:$1" && echo enabled || { sh_tv pm list packages "$1" | grep -qx "package:$1" && echo DISABLED || echo "not installed"; }; }

case "${1:-status}" in
    status)
        echo "Home resolves to:   $(sh_tv cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME | tail -n1)"
        # Android 12 has no `cmd role get-role-holders`; dumpsys role lists it.
        echo "HOME role holder:   $(sh_tv dumpsys role | grep -A1 'name=android.app.role.HOME' | sed -n 's/.*holders=//p' | head -n1)"
        echo "Google TV home:     $(enabled $GOOGLE_HOME)"
        echo "Google TV setup:    $(enabled $SETUP)"
        echo "Official GlassOS:   $(enabled $OFFICIAL)"
        echo "Family GlassOS:     $(enabled $FAMILY)"
        for p in $OFFICIAL $FAMILY; do
            if sh_tv dumpsys activity services "$p/io.github.abhishekkaisar.glassos.HomeWatcher" | grep -q ServiceRecord; then
                echo "Home watcher:       running in $p"
            fi
        done
        echo "In front:           $(focus)"
        ;;
    google-home)
        # The setup app is turned off with the launcher: with only the launcher off, its recovery screen takes Home.
        confirm "pm enable $GOOGLE_HOME" "pm enable $SETUP" "cmd role remove-role-holder android.app.role.HOME $FAMILY" "cmd role remove-role-holder android.app.role.HOME $OFFICIAL"
        sh_tv pm enable "$GOOGLE_HOME"
        sh_tv pm enable "$SETUP"
        sh_tv cmd role remove-role-holder android.app.role.HOME "$FAMILY" || true
        sh_tv cmd role remove-role-holder android.app.role.HOME "$OFFICIAL" || true
        ;;
    official)
        confirm "pm enable $OFFICIAL"
        sh_tv pm enable "$OFFICIAL"
        ;;
    restore-debloat)
        # Re-enables every app listed in tools/out/debloat-done.txt (written when apps were disabled).
        list="$OUT_DIR/debloat-done.txt"
        [ -f "$list" ] || { echo "No $list: nothing recorded as disabled."; exit 1; }
        cmds=(); while read -r p; do [ -n "$p" ] && cmds+=("pm enable $p"); done < <(sort -u "$list")
        confirm "${cmds[@]}"
        while read -r p; do [ -n "$p" ] && sh_tv pm enable "$p"; done < <(sort -u "$list")
        ;;
    remove-family)
        confirm "dpm remove-active-admin $FAMILY/io.github.abhishekkaisar.glassos.AdminReceiver" "uninstall $FAMILY"
        sh_tv dpm remove-active-admin "$FAMILY/io.github.abhishekkaisar.glassos.AdminReceiver" || true
        adb uninstall "$FAMILY"
        ;;
    *) sed -n '2,9p' "$0"; exit 2 ;;
esac
