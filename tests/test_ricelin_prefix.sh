#!/bin/sh
# Safety tests for ricelin-prefix. All data lives below a temporary HOME.
set -eu

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
helper="$here/../configs/hypr/scripts/ricelin-prefix"
work=$(mktemp -d)
cleanup() {
   if [ -n "${hidden_dest:-}" ]; then
       chmod 700 "$hidden_dest" 2>/dev/null || true
   fi
   rm -rf -- "$work"
}
trap cleanup EXIT HUP INT TERM
home="$work/home"
bin="$work/bin"
mkdir -p "$home" "$bin"
original_path=$PATH
export RICELIN_PREFIX_NO_NOTIFY=1
export XDG_OPEN_LOG="$work/xdg-open.args"

cat > "$bin/wineboot" <<'STUB'
#!/bin/sh
[ "${1:-}" = --init ] || exit 2
if [ "${FAIL_WINEBOOT:-0}" = 1 ]; then
    mkdir -p -- "$WINEPREFIX/partial"
    printf 'partial initialization\n' > "$WINEPREFIX/partial/partial-data"
    exit 1
fi
mkdir -p -- "$WINEPREFIX/drive_c" "$WINEPREFIX/dosdevices"
printf 'wine prefix\n' > "$WINEPREFIX/system.reg"
printf 'wine prefix\n' > "$WINEPREFIX/user.reg"
printf 'wine prefix\n' > "$WINEPREFIX/userdef.reg"
STUB
chmod +x "$bin/wineboot"

# Capture the exact argv passed to xdg-open so the compatibility behavior is tested.
cat > "$bin/xdg-open" <<'STUB'
#!/bin/sh
printf '%s\n' "$#" > "$XDG_OPEN_LOG"
printf '%s\n' "$@" >> "$XDG_OPEN_LOG"
STUB
chmod +x "$bin/xdg-open"

ok() { printf '  ok   %s\n' "$1"; }
bad() { printf '  FAIL %s\n' "$1" >&2; exit 1; }
run() { HOME="$home" PATH="$bin:$original_path" sh "$helper" "$@" >/dev/null 2>&1; }
expect_fail() { description=$1; shift; if run "$@"; then bad "expected failure ($description): $*"; else ok "$description"; fi; }
expect_ok() { description=$1; shift; if run "$@"; then ok "$description"; else bad "unexpected failure ($description): $*"; fi; }

prefix="$home/Games/Example/prefix"
exe="$home/Games/Example/game/game.exe"
workdir="$home/Games/Example/game"
mkdir -p "$workdir"
: > "$exe"

expect_ok 'creates a new Wine prefix and marks it' create "$prefix" wine "$exe" "$workdir"
[ -f "$prefix/.ricelin-prefix" ] || bad 'managed-prefix marker was not created'
[ -f "$prefix/system.reg" ] || bad 'wineboot was not invoked'
ok 'new Wine prefix initialized'

expect_ok 'open delegates to xdg-open successfully' open "$prefix" wine "$exe" "$workdir"
[ "$(sed -n '1p' "$XDG_OPEN_LOG")" = "1" ] || bad 'xdg-open did not receive exactly one argument'
[ "$(sed -n '2p' "$XDG_OPEN_LOG")" = "$prefix/drive_c" ] || bad 'xdg-open received an unexpected path or option'
ok 'open passes the absolute drive_c path as its only argument'

# Failed reset of a missing destination must not leave partial files or staging data.
failed_reset_parent="$home/Games/FailedResetMissing"
failed_reset="$failed_reset_parent/prefix"
mkdir -p -- "$failed_reset_parent"
export FAIL_WINEBOOT=1
expect_fail 'failed reset of a missing destination is rejected' reset "$failed_reset" wine "$exe" "$workdir"
unset FAIL_WINEBOOT
[ ! -e "$failed_reset" ] && [ ! -L "$failed_reset" ] || bad 'failed reset left a partial destination'
leftover=$(find "$failed_reset_parent" -mindepth 1 -maxdepth 1 -name '.prefix.ricelin-create.*' -print -quit)
[ -z "$leftover" ] || bad "failed reset left staging data: $leftover"
ok 'failed reset of a missing destination leaves no partial data'

# Failed reset of an existing empty destination must preserve that empty directory.
empty_reset_parent="$home/Games/FailedResetEmpty"
empty_reset="$empty_reset_parent/prefix"
mkdir -p -- "$empty_reset"
export FAIL_WINEBOOT=1
expect_fail 'failed reset of an empty destination is rejected' reset "$empty_reset" wine "$exe" "$workdir"
unset FAIL_WINEBOOT
[ -d "$empty_reset" ] || bad 'failed reset removed the original empty directory'
empty_entry=$(find "$empty_reset" -mindepth 1 -maxdepth 1 -print -quit)
[ -z "$empty_entry" ] || bad "failed reset left partial data in the original empty directory: $empty_entry"
leftover=$(find "$empty_reset_parent" -mindepth 1 -maxdepth 1 -name '.prefix.ricelin-create.*' -print -quit)
[ -z "$leftover" ] || bad "failed reset left staging data: $leftover"
ok 'failed reset of an empty destination preserves it without partial data'

# Failed first-time creation must discard partially initialized staging data.
failed_create_parent="$home/Games/FailedCreate"
failed_create="$failed_create_parent/prefix"
mkdir -p -- "$failed_create_parent"
export FAIL_WINEBOOT=1
expect_fail 'failed first-time creation is rejected' create "$failed_create" wine "$exe" "$workdir"
unset FAIL_WINEBOOT
[ ! -e "$failed_create" ] && [ ! -L "$failed_create" ] || bad 'failed creation left a partial destination'
if find "$failed_create_parent" -maxdepth 1 -name '.prefix.ricelin-create.*' -print -quit | grep -q .; then
    bad 'failed creation left a staging directory'
fi
ok 'failed initial creation leaves no partial prefix or staging directory'

printf 'valuable original data\n' > "$prefix/preserve-on-failure.txt"
export FAIL_WINEBOOT=1
expect_fail 'failed wineboot aborts reset before replacing the original' reset "$prefix" wine "$exe" "$workdir"
unset FAIL_WINEBOOT
[ -f "$prefix/preserve-on-failure.txt" ] || bad 'failed reset lost original prefix data'
grep -q 'valuable original data' "$prefix/preserve-on-failure.txt" || bad 'original prefix data changed'
ok 'old prefix survives a failed reset initialization'

printf 'temporary data\n' > "$prefix/custom-user-file"
expect_ok 'reset only clears a recognized prefix' reset "$prefix" wine "$exe" "$workdir"
[ ! -e "$prefix/custom-user-file" ] || bad 'reset did not clear prefix contents'

no_wine_bin="$work/no-wine-bin"
mkdir -p "$no_wine_bin"
ln -s "$(command -v realpath)" "$no_wine_bin/realpath"
printf 'keep this prefix intact\n' > "$prefix/no-wineboot-sentinel"
if HOME="$home" PATH="$no_wine_bin" RICELIN_PREFIX_NO_NOTIFY=1 /bin/sh "$helper" reset "$prefix" wine "$exe" "$workdir" >/dev/null 2>&1; then
    bad 'reset unexpectedly succeeded without wineboot'
else
    ok 'missing wineboot blocks reset before mutation'
fi
[ -f "$prefix/no-wineboot-sentinel" ] || bad 'missing wineboot caused data loss'
rm -f -- "$prefix/no-wineboot-sentinel"
ok 'prefix data survives missing-wineboot preflight'
[ -f "$prefix/.ricelin-prefix" ] || bad 'reset did not restore marker'
ok 'reset reinitialized the prefix'

printf 'must survive\n' > "$home/keep-me"
expect_fail "reset refuses HOME itself" reset "$home" wine "$exe" "$workdir"
[ -f "$home/keep-me" ] || bad 'HOME sentinel was deleted'
ok 'HOME contents survive blocked reset'

expect_fail "reset refuses the filesystem root" reset / wine "$exe" "$workdir"
[ -f "$home/keep-me" ] || bad 'root-path test damaged HOME'
ok 'root-path test leaves HOME intact'

expect_fail "remove refuses ancestors of HOME" remove "$work" wine "$exe" "$workdir"
[ -d "$home" ] || bad 'ancestor-path test damaged HOME'
ok 'ancestors of HOME are protected'

arbitrary="$home/Downloads"
mkdir -p "$arbitrary"
printf 'do not delete\n' > "$arbitrary/important.txt"
expect_fail "reset refuses arbitrary data directories" reset "$arbitrary" wine "$exe" "$workdir"
[ -f "$arbitrary/important.txt" ] || bad 'arbitrary directory was modified'
ok 'unrecognized non-empty directories are protected'

fake_marker="$home/Games/NotAPrefix"
mkdir -p "$fake_marker"
printf 'important unrelated data\n' > "$fake_marker/notes.txt"
printf 'not a Ricelin marker\n' > "$fake_marker/.ricelin-prefix"
expect_fail 'remove rejects an unrelated directory with a same-named marker file' remove "$fake_marker" wine "" ""
[ -f "$fake_marker/notes.txt" ] || bad 'unrelated directory with a fake marker was deleted'
ok 'unrelated directory survives fake marker'

# Even a structurally valid prefix may not contain the app's files.
game_root="$home/Games/AnotherGame"
mkdir -p "$game_root/drive_c" "$game_root/dosdevices" "$game_root/game"
printf 'reg\n' > "$game_root/system.reg"
printf 'reg\n' > "$game_root/user.reg"
: > "$game_root/game/app.exe"
expect_fail "reset refuses to overlap app files" reset "$game_root" wine "$game_root/game/app.exe" "$game_root/game"
[ -f "$game_root/game/app.exe" ] || bad 'app executable was deleted'
ok 'paths overlapping the app are protected'

source="$prefix"
printf 'clone me\n' > "$source/clone-sentinel"
dest="$home/Games/Other/prefix"
mkdir -p "$dest"
printf 'keep destination\n' > "$dest/keep.txt"
expect_fail "clone refuses non-empty destinations" clone "$source" "$dest" wine "$exe" "$workdir"
[ -f "$dest/keep.txt" ] || bad 'clone overwrote destination data'
ok 'non-empty clone destinations are protected'

# A failed directory scan must not make a populated destination appear empty.
hidden_dest="$home/Games/Other/hidden-destination"
mkdir -p "$hidden_dest"
printf '%s\n' 'keep hidden destination' > "$hidden_dest/clone-sentinel"
chmod 300 "$hidden_dest"

if run clone "$source" "$hidden_dest" wine "$exe" "$workdir"; then
   chmod 700 "$hidden_dest" || true
   bad 'clone accepted a destination whose contents could not be inspected'
else
   chmod 700 "$hidden_dest"
   ok 'clone rejects destinations whose contents cannot be inspected'
fi

grep -q '^keep hidden destination$' "$hidden_dest/clone-sentinel" ||
   bad 'clone modified data in an uninspectable destination'
ok 'uninspectable destination data survives clone refusal'

# Simulate a copy that leaves partial data and then fails.
real_cp=$(command -v cp)
export REAL_CP="$real_cp"
cat > "$bin/cp" <<'STUB'
#!/bin/sh
"$REAL_CP" "$@" || exit $?
destination=
for arg do destination=$arg; done
destination=${destination%/}
printf '%s\n' 'simulated partial copy' > "$destination/.partial-copy-test" || exit 1
exit 1
STUB
chmod +x "$bin/cp"

failed_dest="$home/Games/Other/failed-copy-prefix"
if run clone "$source" "$failed_dest" wine "$exe" "$workdir"; then
    bad 'clone unexpectedly succeeded after simulated cp failure'
else
    ok 'clone rejects a failed copy'
fi
rm -f -- "$bin/cp"

[ ! -e "$failed_dest" ] && [ ! -L "$failed_dest" ] ||
    bad 'failed clone left a final destination behind'
ok 'failed clone leaves no final destination'

leftover=$(find "$home/Games/Other" -mindepth 1 -maxdepth 1 \
    -name '.failed-copy-prefix.ricelin-clone.*' -print -quit)
[ -z "$leftover" ] || bad "failed clone left staging data: $leftover"
ok 'failed clone removes its staging directory'

empty_dest="$home/Games/Other/empty-prefix"
mkdir -p "$empty_dest"
expect_ok 'clone into an empty destination' clone "$source" "$empty_dest" wine "$exe" "$workdir"
[ -f "$empty_dest/clone-sentinel" ] || bad 'clone failed to copy source files'
[ -f "$empty_dest/.ricelin-prefix" ] || bad 'clone did not mark destination'
ok 'clone copied and marked destination'

expect_ok 'removes a managed prefix' remove "$empty_dest" wine "$exe" "$workdir"
[ ! -e "$empty_dest" ] || bad 'remove left managed prefix behind'
ok 'managed prefix removed'

# A final symlink must not be resolved and recursively deleted as its target.
symlink_target="$home/Games/real-prefix"
mkdir -p "$symlink_target/drive_c" "$symlink_target/dosdevices"
printf 'reg\n' > "$symlink_target/system.reg"
printf 'reg\n' > "$symlink_target/user.reg"
symlink="$home/Games/linked-prefix"
ln -s "$symlink_target" "$symlink"
expect_fail "final symlink prefixes are rejected" reset "$symlink" wine "$exe" "$workdir"
[ -f "$symlink_target/system.reg" ] || bad 'symlink target was deleted'
ok 'symlink target survives blocked reset'

expect_fail "trailing-slash symlink aliases are rejected" reset "$symlink/" wine "$exe" "$workdir"
[ -f "$symlink_target/system.reg" ] || bad 'trailing-slash symlink alias damaged target'
ok 'trailing-slash symlink alias leaves target intact'

expect_fail "dot-component symlink aliases are rejected" reset "$symlink/." wine "$exe" "$workdir"
[ -f "$symlink_target/system.reg" ] || bad 'dot-component symlink alias damaged target'
ok 'dot-component symlink alias leaves target intact'

umu_prefix="$home/Games/UMUGame/prefix"
expect_ok 'UMU prefix creation marks a safe directory' create "$umu_prefix" umu "$exe" "$workdir"
[ -f "$umu_prefix/.ricelin-prefix" ] || bad 'UMU prefix marker was not created'
ok 'UMU prefix marked'

# A conventional prefix with a symlink marker is still recognized structurally,
# but cloning it must replace the copied marker link rather than writing through it.
marker_source="$home/Games/MarkerSymlinkSource"
marker_dest="$home/Games/MarkerSymlinkClone"
marker_target="$home/important-external-file.txt"
mkdir -p "$marker_source/drive_c" "$marker_source/dosdevices" "$marker_dest"
printf 'reg\n' > "$marker_source/system.reg"
printf 'reg\n' > "$marker_source/user.reg"
printf 'preserve this external content\n' > "$marker_target"
ln -s "$marker_target" "$marker_source/.ricelin-prefix"
expect_ok 'clone replaces a symlink prefix marker safely' clone "$marker_source" "$marker_dest" wine "" ""
grep -q '^preserve this external content$' "$marker_target" || bad 'clone overwrote external marker target'
[ -f "$marker_dest/.ricelin-prefix" ] || bad 'clone marker missing'
[ ! -L "$marker_dest/.ricelin-prefix" ] || bad 'clone retained a symlink marker'
ok 'external marker target preserved and cloned marker is regular'

printf '\nall prefix safety tests passed\n'
