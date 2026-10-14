#!/bin/sh
# Deploy the PR's Styles & Persona UI and related dock fixes to this user's
# active XDG config tree. Every replaced file is backed up first.
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
config_home=${XDG_CONFIG_HOME:-$HOME/.config}
stamp=$(date +%Y%m%d-%H%M%S)
backup_root="${RICELIN_DEPLOY_BACKUP_ROOT:-$HOME/.local/state/ricelin/backups/style-ui-$stamp}"

files='
hypr/scripts/ricelin-style
hypr/scripts/qs-toggle.sh
quickshell/pill/Pill.qml
quickshell/pill/Settings.qml
quickshell/pill/StylesSurface.qml
quickshell/pill/AddStyleSheet.qml
quickshell/pill/LabeledField.qml
quickshell/pill/DockBody.qml
quickshell/pill/DockButton.qml
quickshell/pill/DockItem.qml
quickshell/pill/Singletons/Styles.qml
quickshell/pill/Singletons/AppLauncher.qml
quickshell/pill/Singletons/Dock.qml
'

die() { printf 'ricelin deploy-style-ui: %s\n' "$*" >&2; exit 1; }

# Fail before touching the live config if this checkout is incomplete.
for rel in $files; do
    [ -f "$root/configs/$rel" ] || die "source file missing: configs/$rel"
done

mkdir -p "$backup_root"
printf 'Backup directory: %s\n' "$backup_root"

for rel in $files; do
    src="$root/configs/$rel"
    dest="$config_home/$rel"
    mode=644
    case "$rel" in hypr/scripts/*) mode=755 ;; esac

    mkdir -p "$(dirname -- "$dest")"

    # If an individual destination is a symlink, update its referent so the
    # existing link stays intact. If it points back at this checkout, there's
    # no separate deployed copy to update.
    src_resolved=$(readlink -f "$src")
    if [ -e "$dest" ] || [ -L "$dest" ]; then
        resolved=$(readlink -f "$dest") || die "cannot resolve symlink: $dest"
        [ -n "$resolved" ] && [ -f "$resolved" ] || die "broken symlink: $dest"
        if [ "$resolved" = "$src_resolved" ]; then
            printf 'Already sourced from checkout: %s\n' "$rel"
            continue
        fi
        # If this individual file is a symlink, replace its referent while
        # retaining the symlink itself.
        if [ -L "$dest" ]; then
            dest="$resolved"
        fi
    fi

    if [ -e "$dest" ]; then
        backup="$backup_root/$rel"
        mkdir -p "$(dirname -- "$backup")"
        if [ -e "$backup" ]; then
            backup="$backup.$(date +%s).$$"
        fi
        cp -p "$dest" "$backup"
        printf 'Backed up: %s\n' "$rel"
    else
        printf 'Installing new: %s\n' "$rel"
    fi

    install -m "$mode" "$src" "$dest"
done

printf '\nDeployment complete. Restart the pill once to load the updated QML.\n'
printf 'Rollback copies are in: %s\n' "$backup_root"
