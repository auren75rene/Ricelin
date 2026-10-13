#!/bin/sh
# Headless integration test for EnvironmentManager QML imports and safe creation.
set -eu

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo=$(CDPATH= cd -- "$here/.." && pwd)

if ! command -v quickshell >/dev/null 2>&1; then
    echo "FAIL: quickshell is required for this test." >&2
    exit 127
fi

work=$(mktemp -d)
qs_pid=
cleanup() {
    if [ -n "${qs_pid:-}" ]; then
        kill "$qs_pid" 2>/dev/null || true
        wait "$qs_pid" 2>/dev/null || true
    fi
    rm -rf -- "$work"
}
trap cleanup EXIT HUP INT TERM

home="$work/home"
config="$work/config"
runtime="$work/runtime"
qml_dir="$work/qml"
game="$home/Games/RicelinRuntimeSmoke"
prefix="$game/prefix"
executable="$game/game.exe"
workdir="$game/work"
log="$work/quickshell.log"

mkdir -p -- "$home" "$config/hypr/scripts" "$runtime" "$qml_dir" "$workdir"
chmod 700 "$runtime"
: > "$executable"
install -m 755 "$repo/configs/hypr/scripts/ricelin-prefix" "$config/hypr/scripts/ricelin-prefix"
install -m 644 "$here/qml_runtime_smoke.qml" "$qml_dir/qml_runtime_smoke.qml"
# Mirror the production import spelling from the pill directory.
ln -s "$repo/configs/quickshell/pill/Singletons" "$qml_dir/Singletons"

env \
    HOME="$home" \
    XDG_CONFIG_HOME="$config" \
    XDG_RUNTIME_DIR="$runtime" \
    RICELIN_TEST_PREFIX="$prefix" \
    RICELIN_TEST_EXECUTABLE="$executable" \
    RICELIN_TEST_WORKDIR="$workdir" \
    QT_QPA_PLATFORM=offscreen \
    QT_QUICK_BACKEND=software \
    quickshell -p "$qml_dir/qml_runtime_smoke.qml" >"$log" 2>&1 &
qs_pid=$!

# Quickshell does not reliably exit on Qt.quit() when no windows are created.
# Wait for the QML success line, then stop only this disposable test process.
attempt=0
while ! grep -Fq 'RICELIN_QML_RUNTIME_SMOKE_DISPATCHED' "$log" 2>/dev/null; do
    if ! kill -0 "$qs_pid" 2>/dev/null; then
        wait "$qs_pid" 2>/dev/null || true
        qs_pid=
        echo "FAIL: Quickshell exited before the QML smoke test completed." >&2
        cat "$log" >&2
        exit 1
    fi

    attempt=$((attempt + 1))
    if [ "$attempt" -ge 100 ]; then
        echo "FAIL: timed out waiting for the QML smoke test." >&2
        cat "$log" >&2
        exit 1
    fi
    sleep 0.1
done

kill "$qs_pid" 2>/dev/null || true
wait "$qs_pid" 2>/dev/null || true
qs_pid=

# execDetached() returns before the helper finishes; poll its marker.
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
