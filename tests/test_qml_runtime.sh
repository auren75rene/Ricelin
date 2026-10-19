#!/bin/sh
# Headless integration test for EnvironmentManager, CameraRec and native desktop launch.
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
prefix_executable="$game/game.exe"
workdir="$game/work dir"
desktop_bin="$home/bin"
desktop_executable="$desktop_bin/argv recorder"
applications="$home/.local/share/applications"
argv_log="$work/argv.log"
log="$work/quickshell.log"

mkdir -p -- "$home" "$home/.config/hypr/scripts" "$config/hypr/scripts" "$runtime" "$qml_dir" "$workdir" "$desktop_bin" "$applications"
chmod 700 "$runtime"
: > "$prefix_executable"

cat > "$desktop_executable" <<'STUB'
#!/bin/sh
{
    for arg do printf 'arg=%s\n' "$arg"; done
    printf 'cwd=%s\n' "$PWD"
} > "$RICELIN_TEST_ARGV_LOG"
STUB
chmod 755 "$desktop_executable"

cat > "$applications/org.ricelin.runtime-smoke.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Ricelin Runtime Smoke
Exec="$desktop_executable" --alpha "value with spaces" --beta
Path=$workdir
Terminal=false
NoDisplay=false
EOF

install -m 755 "$repo/configs/hypr/scripts/ricelin-prefix" "$config/hypr/scripts/ricelin-prefix"
install -m 755 "$repo/configs/hypr/scripts/ricelin-games-scan" "$config/hypr/scripts/ricelin-games-scan"
install -m 755 "$repo/configs/hypr/scripts/ricelin-style" "$home/.config/hypr/scripts/ricelin-style"
install -m 755 "$repo/configs/hypr/scripts/qs-toggle.sh" "$home/.config/hypr/scripts/qs-toggle.sh"
install -m 644 "$here/qml_runtime_smoke.qml" "$qml_dir/qml_runtime_smoke.qml"
# Mirror the production layout so relative imports from Singletons resolve.
ln -s "$repo/configs/quickshell/pill/Singletons" "$qml_dir/Singletons"
ln -s "$repo/configs/quickshell/pill/lib" "$qml_dir/lib"
ln -s "$repo/configs/quickshell/pill" "$qml_dir/Pill"

env \
    HOME="$home" \
    XDG_CONFIG_HOME="$config" \
    XDG_DATA_HOME="$home/.local/share" \
    XDG_RUNTIME_DIR="$runtime" \
    RICELIN_TEST_PREFIX="$prefix" \
    RICELIN_TEST_EXECUTABLE="$prefix_executable" \
    RICELIN_TEST_DESKTOP_EXECUTABLE="$desktop_executable" \
    RICELIN_TEST_ARGV_LOG="$argv_log" \
    RICELIN_TEST_WORKDIR="$workdir" \
    RICELIN_TEST_GAME_FOLDER="$game" \
    QT_QPA_PLATFORM=offscreen \
    QT_QUICK_BACKEND=software \
    quickshell -p "$qml_dir/qml_runtime_smoke.qml" >"$log" 2>&1 &
qs_pid=$!

attempt=0
while ! grep -Fq 'RICELIN_QML_RUNTIME_SMOKE_PASS' "$log" 2>/dev/null; do
    if grep -Fq 'RICELIN_QML_RUNTIME_SMOKE_FAIL:' "$log" 2>/dev/null; then
        echo "FAIL: headless Quickshell runtime smoke reported an error." >&2
        cat "$log" >&2
        exit 1
    fi
    if ! kill -0 "$qs_pid" 2>/dev/null; then
        wait "$qs_pid" 2>/dev/null || true
        qs_pid=
        echo "FAIL: Quickshell exited before the smoke test completed." >&2
        cat "$log" >&2
        exit 1
    fi
    attempt=$((attempt + 1))
    if [ "$attempt" -ge 150 ]; then
        echo "FAIL: timed out waiting for the headless QML smoke test." >&2
        cat "$log" >&2
        exit 1
    fi
    sleep 0.1
done

kill "$qs_pid" 2>/dev/null || true
wait "$qs_pid" 2>/dev/null || true
qs_pid=

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
