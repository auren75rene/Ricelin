# Ricelin Blades — functional contract

Status: design contract for the Blades implementation; not all items below are implemented yet.

## Purpose

Ricelin Blades is the game's visual launch-and-lifecycle surface. It is separate from the Pill: the Pill controls the system; Blades gives each game a stable, visible entry point and manages that game's launch lifecycle.

## Game discovery and identity

- The default library is `$HOME/Games`.
- Each game directory found there must be represented by a blade. Loose game launchers directly inside `Games` should also be discoverable.
- Discovery must not execute candidates. A new game gets a stable identity derived from its path and a persistent registry record, so rescanning cannot create duplicate blades or erase user configuration.
- If a directory contains several plausible launch targets, show a setup/target-selection state rather than guessing and launching an installer, uninstaller, redistributable, or helper executable.
- A discovered game without a configured launch target still gets a blade, visibly marked as needing setup. Selecting it opens the game setup/editor.
- Keep the registry's user choices (name, icon, launch target, arguments, environment, runtime override, prefix and per-game options) when the directory is rescanned. A missing folder should be marked missing rather than silently deleting its record.
- Allow the Games directory to be overridden in configuration. The default remains `$HOME/Games`.

## Stable, adaptive fan layout

- Every discovered/configured game is represented; there is no silent six-game cap.
- Keep each game's order stable between launches and restarts. Do not reorder blades merely because a game was launched more recently.
- Recompute angles and spacing from the complete ordered set whenever games are added, removed, hidden, or restored. A given layout should be symmetric, evenly balanced, and deterministic for a given set of games.
- Persist the stable blade order separately from transient running state. New games are added deterministically; existing IDs keep their relative order.
- The geometry may use balanced concentric arcs/rings when a single arc cannot fit without overlapping blades. Keep each ring balanced, reserve room for the handle and labels, and scale against screen size. If the set is too large for a usable single view, use a deliberate paging/zoom treatment rather than rendering overlapping blades or silently hiding games.
- App icons, fallback initials, labels, runtime labels, and state indicators must remain readable throughout the supported layout range.

## Click contract

- **Single click on an idle, configured blade:** request launch.
- **Single click on a launching or waiting blade:** do not spawn a second launch. Show its current state.
- **Single click on a running blade:** focus its existing game window. If it has multiple windows, cycle through them using deterministic ordering.
- **Double click on a running/launching blade:** request a graceful stop. If graceful stop does not complete, expose a separately confirmed force-stop action; never immediately kill a whole process tree on a double click.
- **Double click on a game waiting for a workspace:** cancel that pending launch.
- Double-click detection must not trigger the single-click launch/focus action first. Use a small single-click disambiguation delay and test it.
- If a game window is opened outside Ricelin, matching should be conservative and must not focus/stop an unrelated similarly named app.

## Workspace allocation policy

- A game may launch only after Ricelin has identified and reserved a genuinely empty, usable regular workspace on the selected/appropriate monitor.
- An empty workspace is a real, non-special workspace with no windows. Do not treat the minimized stash or other special workspaces as available.
- If none is available, leave the game process unstarted and put its blade into a visible `Waiting for empty workspace` state. Automatically retry when workspace/window state changes. Do not create a workspace automatically under this policy.
- A pending launch reserves its selected workspace before the launch process starts, so two queued games cannot claim the same empty workspace.
- If the user cancels a pending launch, release its reservation. If setup/launch fails or times out before a game window appears, release the reservation and report the failure.
- Once launched, associate the actual game window with the reserved workspace by its window address. Never move unrelated windows to make space.
- Keep the monitor/workspace choice in per-game settings where appropriate. If a preferred monitor is unavailable, explain the fallback rather than silently choosing an unsuitable target.

## Runner selection and one-time setup

- Default runner mode is **Auto**. The user can explicitly select an available launcher/runtime when needed; a manual override takes precedence over automatic selection and persists.
- Auto selection is evidence-based, not a promise of compatibility. Prefer a detected Steam-managed install when its Steam identity is known; prefer UMU/Proton when game metadata or a known profile makes it appropriate (especially a confirmed Direct3D 12 path); otherwise choose an available Wine/Wine-Staging profile from the best available evidence. Native games do not get a Wine prefix.
- Keep the selected runner distinct from the resolved/effective runner so `Auto` does not become an invalid executable name in the launch command.
- A failed automatic launch should expose the error and offer other available runners. Do not silently switch prefixes or destructively migrate a prefix when retrying with another runner.
- For ordinary Wine/Wine-Staging games, allocate one dedicated prefix per game under Ricelin's data directory, outside the game installation tree. Initialize it safely and verify success before launch.
- UMU/Proton and Steam-managed games use their own compatible prefix/runtime setup path. Do not create a conflicting Wine prefix for a Steam-managed title.
- Prefix creation, game setup, and launch must be coordinated and observable: `Discovered → Needs setup → Preparing → Ready → Waiting for empty workspace / Launching → Running`, with a visible `Failed` state and a recoverable error.
- Do not treat a launcher process surviving as proof that the actual game window appeared. Track wrapper exit and game-window mapping separately.
- Never run candidates during discovery. Do not assume every `.exe` is the main game; ambiguous launch targets require user selection.
- A failed prefix setup must leave no partial prefix at the final destination; an existing prefix must remain intact when reset/recreation fails.

## Launch execution

- Preserve the current registry data: executable, working directory, arguments, environment variables, graphics/runtime settings, Proton build, MangoHud, Gamescope, FPS limit, window mode/resolution/monitor, and existing launch history.
- Once the correct game window maps, associate/move only that window to the reserved workspace and focus it according to the user's workspace policy.
- When the game exits, clear its running state, release any reservation, restore Ricelin's Game Mode/Do-Not-Disturb/keep-awake settings correctly, and leave its blade available for relaunch.
- Multiple simultaneous games must not corrupt shared game-mode state. Game Mode should turn off only when the last game Ricelin manages has stopped, and it must restore the pre-game settings snapshot.

## Testing contract

Pure logic tests:
- path-to-game identity and idempotent discovery;
- stable order across rescans and recent launches;
- equal-angle and balanced-ring geometry for 0, 1, 2, 6, 7, 12, 13, and larger counts;
- runtime auto-selection vs explicit override;
- workspace eligibility, reservation, queue, cancel, timeout and release;
- click/double-click action disambiguation;
- exact window matching, multiple-window cycling, and no accidental fuzzy matches.

Integration tests in headless Quickshell:
- a new game-folder blade appears without launching any executable;
- the first click enters setup when the launch target is ambiguous;
- a Windows game gets a safe, isolated prefix before it launches;
- no game process starts while every usable workspace is occupied;
- freeing a workspace launches exactly one queued game;
- double-click cancels a waiting launch or gracefully stops a running one;
- clicking a running blade focuses/cycles its windows;
- registry values and stable layout survive a Quickshell restart.

This contract should be implemented in independently testable slices. Do not apply it to the live shell until the relevant CI checks pass and the user explicitly chooses to deploy it.
