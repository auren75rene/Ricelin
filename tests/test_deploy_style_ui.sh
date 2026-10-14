#!/bin/sh
# Exercise the backup-first local UI deployer against isolated XDG paths.
set -eu
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo=$(CDPATH= cd -- "$here/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
home="$work/home"
config="$work/config"
backups="$work/backups"
mkdir -p "$home"

run_deploy() {
    HOME="$home" XDG_CONFIG_HOME="$config" RICELIN_DEPLOY_BACKUP_ROOT="$backups" \
        sh "$repo/tools/deploy-style-ui.sh"
}
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

sh -n "$repo/tools/deploy-style-ui.sh"
run_deploy >"$work/first.log"

[ -x "$config/hypr/scripts/ricelin-style" ] || fail "ricelin-style wasn't installed executable"
[ -x "$config/hypr/scripts/qs-toggle.sh" ] || fail "qs-toggle wasn't installed executable"
[ -f "$config/quickshell/pill/AddStyleSheet.qml" ] || fail "AddStyleSheet.qml wasn't installed"
[ -f "$config/quickshell/pill/Singletons/Styles.qml" ] || fail "Styles singleton wasn't installed"
grep -q 'name: "Add style"' "$config/quickshell/pill/StylesSurface.qml" || fail "Styles UI entry not present"
grep -q 'RICELIN_PERSONA_DIR' "$config/hypr/scripts/ricelin-style" || fail "Persona discovery fix not deployed"

# A second deploy must back up rather than silently replace the first copy.
run_deploy >"$work/second.log"
[ -f "$backups/quickshell/pill/AddStyleSheet.qml" ] || fail "updated QML wasn't backed up"
[ -f "$backups/hypr/scripts/ricelin-style" ] || fail "style registry wasn't backed up"

# A config directory already symlinked into this checkout should be left intact.
other_config="$work/linked-config"
mkdir -p "$other_config/quickshell" "$work/linked-home"
ln -s "$repo/configs/quickshell/pill" "$other_config/quickshell/pill"
HOME="$work/linked-home" XDG_CONFIG_HOME="$other_config" \
    RICELIN_DEPLOY_BACKUP_ROOT="$work/linked-backups" sh "$repo/tools/deploy-style-ui.sh" >"$work/linked.log"
grep -q 'Already sourced from checkout: quickshell/pill/AddStyleSheet.qml' "$work/linked.log" \
    || fail "symlinked source checkout was not detected"

printf '%s\n' "all style UI deployment checks passed"
