#!/bin/sh
# Headless integration test for EnvironmentManager QML imports and safe creation.
set -eu

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo=$(CDPATH= cd -- "$here/.." && pwd)

if ! command -v quickshell >/dev/null 2>&1; then
    echo "FAIL: quickshell is required for this test." >&2
    exit 127
fi
if ! command -v timeout >/dev/null 2>&1; then
    echo "FAIL: timeout is required for this test." >&2
    exit 127
fi

work=$(mktemp -d)
cleanup() {
    rm -rf -- "$work"
}
trap cleanup EXIT HUP INT TERM

home="$work/home"
config="$work/config"
runtime="$work/runtime"
game="$home/Games/RicelinRuntimeSmoke"
prefix="$game/prefix"
executable="$game/game.exe"
workdir="$game/work"
log="$work/quickshell.log"

mkdir -p -- "$home" "$config/hypr/scripts" "$runtime" "$workdir"
chmod 700 "$runtime"
: > "$executable"
install -m 755 "$repo/configs/hypr/scripts/ricelin-prefix" "$config/hypr/scripts/ricelin-prefix"

if ! env \
    HOME="$home" \
    XDG_CONFIG_HOME="$config" \
    XDG_RUNTIME_DIR="$runtime" \
    RICELIN_TEST_PREFIX="$prefix" \
    RICELIN_TEST_EXECUTABLE="$executable" \
    RICELIN_TEST_WORKDIR="$workdir" \
    QT_QPA_PLATFORM=offscreen \
    QT_QUICK_BACKEND=software \
    timeout 15s quickshell -p "$here/qml_runtime_smoke.qml" >"$log" 2>&1; then
    echo "FAIL: Quickshell did not complete the headless QML smoke test." >&2
    cat "$log" >&2
    exit 1
fi

if ! grep -Fq 'RICELIN_QML_RUNTIME_SMOKE_DISPATCHED' "$log"; then
    echo "FAIL: QML did not import EnvironmentManager and dispatch its create action." >&2
    cat "$log" >&2
    exit 1
fi

# Quickshell.execDetached() returns before the helper finishes; poll its marker.
# runner=umu takes the helper's marker-only path and needs no Wine/UMU installed.
attempt=0
while [ ! -f "$prefix/.ricelin-prefix" ]; do
    attempt=$((attempt + 1))
    if [ "$attempt" -ge 100 ]; then
        echo "FAIL: dispatched prefix action did not create its sandbox marker." >&2
        cat "$log" >&2
        exit 1
    fi
    sleep 0.1
done

if [ "$(cat "$prefix/.ricelin-prefix")" != 'Ricelin-managed Wine/Proton prefix' ]; then
    echo "FAIL: unexpected prefix marker content." >&2
    cat "$log" >&2
    exit 1
fi

echo "all Quickshell runtime smoke checks passed"
