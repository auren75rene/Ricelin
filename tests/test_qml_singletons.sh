#!/bin/sh
# Ensure every QML file declaring pragma Singleton is registered in this module's qmldir.
set -eu

here="$(cd "$(dirname "$0")" && pwd)"
singleton_dir="$here/../configs/quickshell/pill/Singletons"
qmldir="$singleton_dir/qmldir"

[ -d "$singleton_dir" ] || { echo "missing singleton directory: $singleton_dir" >&2; exit 1; }
[ -f "$qmldir" ] || { echo "missing qmldir: $qmldir" >&2; exit 1; }

count=0
failed=0
for file in "$singleton_dir"/*.qml; do
    [ -f "$file" ] || continue
    if grep -Eq '^[[:space:]]*pragma[[:space:]]+Singleton([[:space:]]|$)' "$file"; then
        count=$((count + 1))
        name=${file##*/}
        type=${name%.qml}
        if grep -Eq "^[[:space:]]*singleton[[:space:]]+$type[[:space:]]+$name[[:space:]]*$" "$qmldir"; then
            printf '  ok   %s is registered\n' "$name"
        else
            printf '  FAIL %s declares pragma Singleton but is absent from qmldir\n' "$name" >&2
            failed=1
        fi
    fi
done

[ "$count" -gt 0 ] || { echo "no QML singleton declarations found" >&2; exit 1; }
[ "$failed" -eq 0 ] || exit 1
printf 'all %s QML singletons are registered\n' "$count"
