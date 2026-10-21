pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../lib/desktopentry.js" as DesktopImport

/**
 * Execution layer: turns an AppRegistry record into a real process and keeps
 * track of it while it runs. One Process object is created per launch via
 * `procComponent.createObject()` — Process is a plain QtObject (see
 * Quickshell.Io docs), so this is the documented way to have more than one
 * in flight at once, rather than pre-declaring a fixed pool of slots.
 *
 * Environment variables are passed through Process.environment rather than
 * built into a `sh -c "VAR=val cmd"` string: several of these paths contain
 * spaces (the Cyberpunk working directory is literally ".../Cyberpunk 2077"),
 * and the structured command/environment/workingDirectory properties avoid
 * shell-quoting them entirely.
 *
 * `wine` and `umu-run` both block for the life of the game, so Process.running
 * going false *is* "the game closed" — no separate pgrep polling loop needed.
 * Stop sends SIGTERM (graceful); Force Stop pkills the executable's own path
 * so a wedged Windows process tree can't block the tile forever.
 */
Singleton {
    id: root

    /** True while auto-toggling Flags.gameMode for category:"game" launches. Flip off if you'd rather drive Game Mode by hand. */
    property bool autoGameMode: true

    /** appId -> { startedAt, pid }. Reassigned wholesale (never mutated in place) so isRunning()/pid() bindings refresh. */
    property var runningIds: ({})

    /** appId -> live Process, kept outside runningIds since UI never binds to the process object itself. */
    property var _procs: ({})
    property var _stopRequested: ({})
    property var pendingStarts: ({}) // appId -> token while prefix preparation is in flight
    property int nextStartToken: 0
    property int _runningGameCount: 0

    signal preparationFailed(string appId, string message)
    signal launchFailed(string appId, string message)
    signal launchDeferred(string appId, string message)

    function isRunning(appId) {
        return appId in root.runningIds;
    }

    function pidFor(appId) {
        var r = root.runningIds[appId];
        return r ? r.pid : 0;
    }

    function startedAt(appId) {
        var r = root.runningIds[appId];
        return r ? r.startedAt : 0;
    }

    function isPending(appId) {
        return appId in root.pendingStarts;
    }

    function cancelPending(appId) {
        if (!(appId in root.pendingStarts))
            return false;
        var next = Object.assign({}, root.pendingStarts);
        delete next[appId];
        root.pendingStarts = next;
        // The safety helper is allowed to finish initializing its staged prefix,
        // but the stale callback is ignored and never starts the game.
        return true;
    }

    function clearPending(appId, token) {
        if (root.pendingStarts[appId] !== token)
            return false;
        var next = Object.assign({}, root.pendingStarts);
        delete next[appId];
        root.pendingStarts = next;
        return true;
    }

    function dllOverrideString(overrides) {
        if (!overrides)
            return "";
        var parts = [];
        for (var dll in overrides) {
            var mode = overrides[dll];
            var code = mode === "native" ? "n" : mode === "builtin" ? "b" : mode === "native,builtin" ? "n,b" : mode === "disabled" ? "" : "";
            parts.push(dll + "=" + code);
        }
        return parts.join(";");
    }

    function dirName(p) {
        var i = String(p).lastIndexOf("/");
        return i > 0 ? p.slice(0, i) : p;
    }

    /** Resolve a native desktop entry by persisted ID, then support old ID/name records. */
    function desktopEntryFor(app) {
        if (!app || app.runner !== "native")
            return null;
        return DesktopImport.findEntry(DesktopEntries.applications.values || [], app);
    }

    /**
     * Resolve Auto once for execution; the stored runner remains "auto".
     * Any effective Wine-family runner receives a dedicated per-game prefix if
     * an older/manual registry entry didn't have one yet.
     */
    function effectiveRecord(app) {
        var normalized = AppRegistry.normalizeRecord(app);
        var effective = normalized;
        if (normalized.runner === "auto") {
            var recommendation = RuntimeManager.recommend(normalized);
            effective = Object.assign({}, normalized, {
                runner: recommendation.runner,
                protonBuild: recommendation.protonBuild || normalized.protonBuild,
                runnerReason: recommendation.reason
            });
        }
        if (["wine", "wine-staging", "umu"].indexOf(effective.runner) >= 0
                && !String(effective.prefix || "")) {
            effective.prefix = AppRegistry.dataHome + "/ricelin/prefixes/" + String(effective.id);
        }
        return effective;
    }

    function effectiveRunnerFor(app) {
        return root.effectiveRecord(app).runner;
    }

    /** Builds { command, environment, workingDirectory } for the effective runner. */
    function buildInvocation(app) {
        var normalized = AppRegistry.normalizeRecord(app);
        if (normalized.runner === "auto" && !RuntimeManager.ready)
            return { command: [], environment: {}, workingDirectory: "", error: "Runtime detection has not completed." };

        normalized = root.effectiveRecord(normalized);
        if (normalized.runner === "steam" && !/^[0-9]+$/.test(String(normalized.steamAppId || ""))) {
            return {
                command: [],
                environment: {},
                workingDirectory: "",
                error: "Steam needs this game's numeric App ID. Set it in the game editor or choose another runner."
            };
        }
        var env = Object.assign({}, normalized.env || {});
        var overrideStr = root.dllOverrideString(normalized.dllOverrides);
        if (overrideStr.length > 0) env.WINEDLLOVERRIDES = overrideStr;
        if (normalized.performance && normalized.performance.fpsLimit > 0) env.DXVK_FRAME_RATE = String(normalized.performance.fpsLimit);
        if (normalized.performance && normalized.performance.mangohud) env.MANGOHUD = "1";

        var command;
        var desktopEntry = normalized.runner === "native" ? root.desktopEntryFor(normalized) : null;
        var workingDirectory = DesktopImport.workingDirectoryFor(normalized, desktopEntry);
        var rt = normalized.runtime || {};
        if (normalized.runner === "umu") {
            env.GAMEID = env.GAMEID || (normalized.umuId && normalized.umuId.length > 0 ? normalized.umuId : ("umu-" + normalized.id));
            if (normalized.prefix) env.WINEPREFIX = normalized.prefix;
            env.PROTONPATH = env.PROTONPATH || normalized.protonBuild || rt.build || "GE-Proton";
            command = ["umu-run", normalized.executable].concat(normalized.args || []);
        } else if (normalized.runner === "steam") {
            command = ["steam", "-applaunch", normalized.steamAppId || normalized.id].concat(normalized.args || []);
        } else if (normalized.runner === "wine" || normalized.runner === "wine-staging") {
            if (normalized.prefix) env.WINEPREFIX = normalized.prefix;
            var wineBin = normalized.runner === "wine-staging" && !root.wineIsStaging ? "wine-staging" : "wine";
            command = [wineBin, normalized.executable].concat(normalized.args || []);
        } else {
            command = DesktopImport.nativeCommand(normalized, desktopEntry);
        }
        if (normalized.performance && normalized.performance.mangohud) command = ["mangohud"].concat(command);
        if (normalized.performance && normalized.performance.gamescope) command = ["gamescope", "--"].concat(command);
        return {
            command: command,
            environment: env,
            workingDirectory: workingDirectory,
            runner: normalized.runner,
            runnerReason: normalized.runnerReason || ""
        };
    }

    /** True once RuntimeManager has confirmed the plain `wine` binary already answers to Wine-Staging, so buildInvocation doesn't reach for a separate wine-staging binary that would just be missing. */
    readonly property bool wineIsStaging: RuntimeManager.wineVersion.toLowerCase().indexOf("staging") >= 0

    Component {
        id: procComponent
        Process {
            id: processRoot
            property string capturedStderr: ""
            stdout: StdioCollector {}
            stderr: StdioCollector {
                onStreamFinished: processRoot.capturedStderr = this.text
            }
        }
    }

    /**
     * Prepare a Wine-family prefix before starting the game. Preparation is
     * asynchronous and tokenized so a double-click can cancel the launch
     * continuation without killing prefix initialization halfway through.
     */
    function launch(appId, useGameMode, beforeStart) {
        if (useGameMode === undefined)
            useGameMode = true;

        function mayStart() {
            if (typeof beforeStart !== "function")
                return true;
            try {
                if (beforeStart())
                    return true;
            } catch (error) {
                console.warn("Ricelin: pre-launch workspace check failed", appId, String(error));
            }
            root.launchDeferred(String(appId), "The reserved workspace is no longer empty. Waiting for an empty workspace.");
            return false;
        }

        var app = AppRegistry.byId(appId);
        if (!app || root.isRunning(appId) || root.isPending(appId))
            return false;
        if (app.needsSetup || app.folderMissing || !String(app.executable || "")) {
            var setupMessage = app.folderMissing
                ? "The game's folder is missing."
                : "Choose the game's launch executable before launching it.";
            Quickshell.execDetached(["notify-send", "-u", "normal", "-a", "Ricelin", "Game needs setup: " + app.name, setupMessage]);
            return false;
        }

        var effective = root.effectiveRecord(app);
        if (effective.prefix && String(app.prefix || "") !== effective.prefix
                && ["wine", "wine-staging", "umu"].indexOf(effective.runner) >= 0) {
            AppRegistry.update(appId, { prefix: effective.prefix });
            app = AppRegistry.byId(appId);
            effective = root.effectiveRecord(app);
        }

        var inv = root.buildInvocation(app);
        if (inv.error || !inv.command || inv.command.length === 0) {
            var launchError = inv.error || "No launch command was resolved.";
            console.warn("Ricelin: cannot launch", app.name, launchError);
            Quickshell.execDetached(["notify-send", "-u", "normal", "-a", "Ricelin", "Cannot launch " + app.name, launchError]);
            return false;
        }

        if (["wine", "wine-staging", "umu"].indexOf(effective.runner) >= 0) {
            var token = String(Date.now()) + "-" + String(++root.nextStartToken);
            root.pendingStarts = Object.assign({}, root.pendingStarts, { [appId]: token });
            var accepted = EnvironmentManager.ensurePrefix(effective, function(ok, message) {
                if (!root.clearPending(appId, token))
                    return; // canceled or superseded while the helper was running

                if (!ok) {
                    var reason = String(message || "Prefix preparation failed.");
                    root.preparationFailed(appId, reason);
                    Quickshell.execDetached(["notify-send", "-u", "normal", "-a", "Ricelin", "Could not prepare " + app.name, reason]);
                    return;
                }

                var current = AppRegistry.byId(appId);
                if (!current || root.isRunning(appId))
                    return;
                var readyInvocation = root.buildInvocation(current);
                if (readyInvocation.error || !readyInvocation.command || readyInvocation.command.length === 0) {
                    var reason2 = String(readyInvocation.error || "No launch command was resolved after prefix setup.");
                    root.launchFailed(appId, reason2);
                    Quickshell.execDetached(["notify-send", "-u", "normal", "-a", "Ricelin", "Cannot launch " + current.name, reason2]);
                    return;
                }
                if (!mayStart())
                    return;
                root.startInvocation(appId, useGameMode, readyInvocation);
            });
            if (!accepted) {
                root.clearPending(appId, token);
                return false;
            }
            return true;
        }

        if (!mayStart())
            return false;
        return root.startInvocation(appId, useGameMode, inv);
    }

    function startInvocation(appId, useGameMode, inv) {
        var app = AppRegistry.byId(appId);
        if (!app || root.isRunning(appId) || !inv || !inv.command || inv.command.length === 0)
            return false;

        var proc = procComponent.createObject(root, {
            command: inv.command,
            environment: inv.environment,
            workingDirectory: inv.workingDirectory,
            running: true
        });
        if (!proc)
            return false;

        root._procs[appId] = proc;
        root._stopRequested = Object.assign({}, root._stopRequested, { [appId]: false });
        root.runningIds = Object.assign({}, root.runningIds, {
            [appId]: { startedAt: Date.now(), pid: 0 }
        });

        AppRegistry.recordLaunch(appId);

        if (app.category === "game" && root.autoGameMode && useGameMode) {
            root._runningGameCount++;
            if (root._runningGameCount === 1)
                Flags.gameMode = true;
        }

        pidTimer.createObject(root, { appId: appId, proc: proc });

        proc.exited.connect(function (exitCode, exitStatus) {
            var launched = root.runningIds[appId];
            var elapsedMs = launched ? Date.now() - launched.startedAt : 0;
            var stopFlags = Object.assign({}, root._stopRequested);
            var intentionallyStopped = stopFlags[appId] === true;
            delete stopFlags[appId];
            root._stopRequested = stopFlags;

            if (exitCode !== 0 && !intentionallyStopped) {
                var detail = String(proc.capturedStderr || "").trim();
                if (detail.length === 0)
                    detail = "Process exited with status " + exitCode + ".";
                if (detail.length > 420)
                    detail = detail.slice(0, 417) + "...";
                console.warn("Ricelin: application exited with status", exitCode, app.name, detail);
                if (elapsedMs < 5000) {
                    root.launchFailed(appId, detail);
                    Quickshell.execDetached(["notify-send", "-u", "normal", "-a", "Ricelin", "Could not start " + app.name, detail]);
                }
            }

            delete root._procs[appId];
            var next = Object.assign({}, root.runningIds);
            delete next[appId];
            root.runningIds = next;
            if (app.category === "game" && root.autoGameMode && useGameMode) {
                root._runningGameCount = Math.max(0, root._runningGameCount - 1);
                if (root._runningGameCount === 0)
                    Flags.gameMode = false;
            }
            proc.destroy();
        });
        return true;
    }

    /** A one-shot Timer component rather than a single shared Timer, since several launches can be settling their pid at once. */
    Component {
        id: pidTimer
        Timer {
            property string appId: ""
            property var proc: null
            interval: 400
            running: true
            onTriggered: {
                if (proc && root.isRunning(appId)) {
                    var next = Object.assign({}, root.runningIds);
                    if (next[appId])
                        next[appId] = { startedAt: next[appId].startedAt, pid: proc.processId || 0 };
                    root.runningIds = next;
                }
                destroy();
            }
        }
    }

    /** Graceful stop: SIGTERM to our tracked process (Process.running = false), giving Wine/UMU a chance to shut the game down cleanly. */
    function stop(appId) {
        var proc = root._procs[appId];
        if (proc) {
            root._stopRequested = Object.assign({}, root._stopRequested, { [appId]: true });
            proc.running = false;
        }
    }

    /** Best-effort tree kill for a wedged process: matches the game's own executable path rather than the wine/umu-run wrapper, so the wrapper notices its child died and exits on its own — which fires the normal exited() cleanup above. */
    function forceStop(appId) {
        var proc = root._procs[appId];
        var pid = proc ? (proc.processId || 0) : root.pidFor(appId);
        if (pid <= 0) return;
        root._stopRequested = Object.assign({}, root._stopRequested, { [appId]: true });
       Quickshell.execDetached(["sh", "-c", 'kill_tree() { for c in $(pgrep -P "$1" 2>/dev/null); do kill_tree "$c"; done; kill -KILL "$1" 2>/dev/null; }; kill_tree "$1"', "_", String(pid)]);
    }

    // ---- Environment (prefix) actions -------------------------------------
    // Resolve Auto before invoking the safety helper; it accepts only concrete Wine/UMU runners.
    function createPrefix(app) { return EnvironmentManager.create(root.effectiveRecord(app)); }
    function openPrefixFiles(app) { return EnvironmentManager.openFiles(root.effectiveRecord(app)); }
    function runWinetricks(app) { return EnvironmentManager.winetricks(root.effectiveRecord(app)); }
    function clonePrefix(app, destPath) { return EnvironmentManager.clone(root.effectiveRecord(app), destPath); }
    function resetPrefix(app) { return EnvironmentManager.reset(root.effectiveRecord(app)); }
    function deletePrefix(app) { return EnvironmentManager.remove(root.effectiveRecord(app)); }

    // ---- File pickers (zenity, falling back to kdialog) -------------------

    Component {
        id: pickerComponent
        Process {
            stdout: StdioCollector {}
        }
    }

    function pickFile(callback, title) {
        var pickerTitle = title || "Select executable";
        root._runPicker(RuntimeManager.hasZenity
            ? ["zenity", "--file-selection", "--title=" + pickerTitle]
            : RuntimeManager.hasKdialog
                ? ["kdialog", "--getopenfilename"]
                : [], callback);
    }

    function pickFolder(callback) {
        root._runPicker(RuntimeManager.hasZenity
            ? ["zenity", "--file-selection", "--directory", "--title=Select folder"]
            : RuntimeManager.hasKdialog
                ? ["kdialog", "--getexistingdirectory"]
                : [], callback);
    }

    function _runPicker(command, callback) {
        if (command.length === 0) {
            callback("");
            return;
        }
        var proc = pickerComponent.createObject(root, { command: command, running: true });
        proc.exited.connect(function () {
            var out = proc.stdout.text ? String(proc.stdout.text).trim() : "";
            callback(out);
            proc.destroy();
        });
    }
}
