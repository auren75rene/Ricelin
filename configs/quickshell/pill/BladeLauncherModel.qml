pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import "Singletons"
import "lib/blades.js" as Blades

/**
 * Game/app model for the corner fan. AppRegistry is the persistent source of
 * launch configuration; this model owns the live window view, workspace
 * reservations, queued launches and stop requests.
 */
QtObject {
    id: root

    property string screenName: ""
    property var queuedIds: ({})
    property var reservedWorkspaces: ({}) // workspace key -> app ID
    property var launchTargets: ({})       // app ID -> {workspaceId, workspaceName, monitor, key, startedAt}
    property var stoppingIds: ({})         // app ID -> request timestamp
    property var failedIds: ({})           // app ID -> readable failure
    readonly property real queuePollMs: 800
    readonly property real launchTimeoutMs: 90000
    readonly property real stopTimeoutMs: 15000

    /** Live Hyprland clients normalized to plain values for deterministic matching. */
    readonly property var windows: {
        var tl = Hyprland.toplevels.values || [];
        var out = [];
        for (var i = 0; i < tl.length; ++i) {
            var t = tl[i];
            if (!t)
                continue;
            var ipc = t.lastIpcObject;
            var cls = ipc && ipc.class ? ipc.class
                : (t.wayland && t.wayland.appId ? t.wayland.appId : "");
            out.push({
                address: Dock.hex(t.address),
                cls: cls,
                title: t.title || (ipc && ipc.title ? ipc.title : ""),
                workspace: t.workspace ? t.workspace.name : "",
                workspaceId: t.workspace ? Number(t.workspace.id || 0) : 0,
                monitor: t.workspace && t.workspace.monitor ? t.workspace.monitor.name : ""
            });
        }
        return out;
    }

    /** Hyprland workspaces, including monitor names, as plain data for the selector. */
    readonly property var workspaces: {
        var src = Hyprland.workspaces.values || [];
        var out = [];
        for (var i = 0; i < src.length; ++i) {
            var w = src[i];
            if (!w)
                continue;
            out.push({
                id: Number(w.id || 0),
                name: String(w.name || ""),
                monitor: w.monitor ? String(w.monitor.name || "") : ""
            });
        }
        return out;
    }

    function desktopFor(app) {
        if (!app || AppLauncher.effectiveRunnerFor(app) !== "native")
            return null;
        var entries = DesktopEntries.applications.values || [];
        for (var i = 0; i < entries.length; ++i) {
            var e = entries[i];
            if (e && !e.noDisplay && e.id &&
                    ((app.desktopEntryId && String(e.id) === String(app.desktopEntryId))
                     || String(e.id) === String(app.id)))
                return e;
        }
        var wanted = String(app.name || "").toLowerCase();
        for (var j = 0; j < entries.length; ++j) {
            var e2 = entries[j];
            if (e2 && !e2.noDisplay && wanted.length > 0 && String(e2.name || "").toLowerCase() === wanted)
                return e2;
        }
        return null;
    }

    /** Windows belonging to the app, if any are currently managed by Hyprland. */
    function windowsFor(app) {
        if (!app)
            return [];
        var entry = root.desktopFor(app);
        var out = [];
        var src = root.windows;
        for (var i = 0; i < src.length; ++i)
            if (Blades.matchesWindow(app, src[i], entry))
                out.push(src[i]);
        return out;
    }

    /** Every game, including a folder that still needs a launch target, gets a blade. */
    readonly property var apps: {
        var picked = Blades.select(AppRegistry.apps, 0);
        var out = [];
        for (var i = 0; i < picked.length; ++i) {
            var app = picked[i];
            if (app.needsSetup || app.folderMissing || !app.executable) {
                out.push(app);
                continue;
            }
            if (AppLauncher.effectiveRunnerFor(app) !== "native") {
                out.push(app);
                continue;
            }
            var entry = root.desktopFor(app);
            out.push(entry ? Object.assign({}, app, { desktopEntry: entry }) : app);
        }
        return out;
    }

    readonly property int count: root.apps.length

    function appAt(index) {
        return index >= 0 && index < root.apps.length ? root.apps[index] : null;
    }

    function stateFor(index) {
        var app = root.appAt(index);
        if (!app)
            return "idle";
        if (app.id in root.stoppingIds)
            return "stopping";
        if (app.id in root.failedIds)
            return "failed";
        if (root.windowsFor(app).length > 0)
            return "running";
        if (app.id in root.launchTargets)
            return "launching";
        if (app.id in root.queuedIds)
            return "waiting";
        if (AppLauncher.isRunning(app.id))
            return "launching";
        return "idle";
    }

    function labelFor(index) {
        var app = root.appAt(index);
        return app ? RuntimeManager.profileFor(AppLauncher.effectiveRunnerFor(app)).shortLabel : "";
    }

    function targetMonitorFor(app) {
        var configured = app && app.window ? String(app.window.monitor || "") : "";
        if (configured.length > 0 && configured.toLowerCase() !== "automatic" && configured.toLowerCase() !== "auto")
            return configured;
        if (root.screenName.length > 0)
            return root.screenName;
        return Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "";
    }

    function emptyWorkspaceFor(app) {
        return Blades.chooseEmptyWorkspace(
            root.workspaces,
            root.windows,
            root.reservedWorkspaces,
            root.targetMonitorFor(app)
        );
    }

    function clearObjectKey(object, key) {
        var next = Object.assign({}, object || {});
        delete next[key];
        return next;
    }

    function releaseTarget(appId) {
        var target = root.launchTargets[appId];
        if (target) {
            root.reservedWorkspaces = root.clearObjectKey(root.reservedWorkspaces, target.key);
            root.launchTargets = root.clearObjectKey(root.launchTargets, appId);
        }
    }

    function failApp(appId, reason) {
        root.failedIds = Object.assign({}, root.failedIds, { [appId]: String(reason) });
    }

    function beginLaunch(app, workspace) {
        if (!app || !workspace || !Number(workspace.id) || Number(workspace.id) <= 0)
            return false;

        var key = Blades.workspaceKey(workspace);
        if (!key || root.reservedWorkspaces[key])
            return false;

        var target = {
            workspaceId: Number(workspace.id),
            workspaceName: String(workspace.name || workspace.id),
            monitor: String(workspace.monitor || root.screenName),
            key: key,
            startedAt: Date.now()
        };

        root.failedIds = root.clearObjectKey(root.failedIds, app.id);
        root.queuedIds = root.clearObjectKey(root.queuedIds, app.id);
        root.reservedWorkspaces = Object.assign({}, root.reservedWorkspaces, { [key]: app.id });
        root.launchTargets = Object.assign({}, root.launchTargets, { [app.id]: target });

        // Switching to the already-empty workspace before spawning ensures the
        // new toplevel naturally starts there; reconciliation moves it by address
        // if the launcher/window manager places it elsewhere.
        Hyprland.dispatch('hl.dsp.focus({workspace="' + target.workspaceName + '"})');
        if (!AppLauncher.launch(app.id, true)) {
            root.releaseTarget(app.id);
            root.failApp(app.id, "The selected runner could not start. Check the runtime and launch settings.");
            return false;
        }
        return true;
    }

    function configure(index) {
        var app = root.appAt(index);
        if (!app)
            return;
        if (app.folderMissing) {
            root.failApp(app.id, "The game folder is missing. Restore it or update the Games directory, then rescan.");
            Quickshell.execDetached(["notify-send", "-u", "normal", "-a", "Ricelin", "Game folder missing", app.name]);
            return;
        }
        // Discovery is read-only and never executes guessed targets. A folder
        // with an ambiguous/no executable asks the user to choose the real one.
        AppLauncher.pickFile(function(path) {
            if (!path || String(path).length === 0)
                return;
            var current = AppRegistry.byId(app.id);
            if (!current)
                return;
            var selected = String(path);
            var effectiveRunner = current.runner === "auto"
                ? RuntimeManager.recommend(Object.assign({}, current, { executable: selected })).runner
                : current.runner;
            var prefix = String(current.prefix || "");
            if (/\.exe$/i.test(selected) && ["wine", "wine-staging", "umu"].indexOf(effectiveRunner) >= 0
                    && prefix.length === 0)
                prefix = AppRegistry.dataHome + "/ricelin/prefixes/" + current.id;
            AppRegistry.update(current.id, {
                executable: selected,
                workingDirectory: selected.slice(0, selected.lastIndexOf("/")) || current.gameFolder,
                prefix: prefix,
                needsSetup: false,
                folderMissing: false
            });
            root.failedIds = root.clearObjectKey(root.failedIds, current.id);
            Quickshell.execDetached(["notify-send", "-u", "normal", "-a", "Ricelin", "Game configured", current.name + " is ready. Click its blade to launch."]);
        }, "Choose the main executable for " + app.name);
    }

    function launch(index) {
        var app = root.appAt(index);
        if (!app)
            return;

        if (app.folderMissing) {
            root.configure(index);
            return;
        }
        if (app.needsSetup || !app.executable) {
            root.configure(index);
            return;
        }

        // Existing windows are navigation targets, never a reason to spawn a duplicate.
        var existing = root.windowsFor(app);
        if (existing.length > 0) {
            var active = Hyprland.activeToplevel;
            var activeAddress = active && active.address ? Dock.hex(active.address) : "";
            var target = Blades.nextWindow(existing, activeAddress);
            if (target)
                Dock.focusWindow(target, root.screenName);
            root.failedIds = root.clearObjectKey(root.failedIds, app.id);
            return;
        }

        if (app.id in root.queuedIds || app.id in root.launchTargets || AppLauncher.isRunning(app.id))
            return;

        root.failedIds = root.clearObjectKey(root.failedIds, app.id);
        var workspace = root.emptyWorkspaceFor(app);
        if (!workspace) {
            // Queue intent only. No process, Wine prefix, or Steam launch starts
            // until a usable empty workspace is found.
            root.queuedIds = Object.assign({}, root.queuedIds, {
                [app.id]: { requestedAt: Date.now(), monitor: root.targetMonitorFor(app) }
            });
            return;
        }

        root.beginLaunch(app, workspace);
    }

    function stop(index) {
        var app = root.appAt(index);
        if (!app)
            return;

        // Double-clicking a queued game cancels it. It never launches later
        // without the user asking again.
        if (app.id in root.queuedIds) {
            root.queuedIds = root.clearObjectKey(root.queuedIds, app.id);
            root.failedIds = root.clearObjectKey(root.failedIds, app.id);
            return;
        }

        if (app.id in root.launchTargets) {
            if (AppLauncher.isRunning(app.id))
                AppLauncher.stop(app.id);
            root.releaseTarget(app.id);
            root.stoppingIds = Object.assign({}, root.stoppingIds, { [app.id]: Date.now() });
            return;
        }

        if (AppLauncher.isRunning(app.id)) {
            root.stoppingIds = Object.assign({}, root.stoppingIds, { [app.id]: Date.now() });
            AppLauncher.stop(app.id);
            return;
        }

        // A window may have been started outside Ricelin, or a Steam CLI wrapper
        // may have exited while its game remains. Request a polite compositor
        // close; never force-kill a process tree on a double click.
        var existing = root.windowsFor(app);
        for (var i = 0; i < existing.length; ++i) {
            var address = Dock.hex(existing[i].address);
            if (address.length > 0)
                Hyprland.dispatch('hl.dsp.window.close({window="address:' + address + '"})');
        }
        if (existing.length > 0)
            root.stoppingIds = Object.assign({}, root.stoppingIds, { [app.id]: Date.now() });
        else
            root.failedIds = root.clearObjectKey(root.failedIds, app.id);
    }

    function reconcileLaunchTargets() {
        var ids = Object.keys(root.launchTargets);
        for (var i = 0; i < ids.length; ++i) {
            var appId = ids[i];
            var target = root.launchTargets[appId];
            var app = AppRegistry.byId(appId);
            if (!app) {
                root.releaseTarget(appId);
                continue;
            }

            var found = root.windowsFor(app);
            if (found.length > 0) {
                var w = found[0];
                var address = Dock.hex(w.address);
                if (address && Number(target.workspaceId) > 0 &&
                    Number(w.workspaceId || 0) !== Number(target.workspaceId)) {
                    Hyprland.dispatch('hl.dsp.window.move({ workspace = ' + Number(target.workspaceId)
                        + ', follow = false, window = "address:' + address + '" })');
                }
                // Focus after the specific move; Dock.focusWindow uses the same
                // Lua-aware dispatch implementation as the rest of Ricelin.
                Dock.focusWindow(Object.assign({}, w, { workspace: target.workspaceName }), target.monitor);
                root.releaseTarget(appId);
                root.stoppingIds = root.clearObjectKey(root.stoppingIds, appId);
                continue;
            }

            if (Date.now() - Number(target.startedAt || 0) > root.launchTimeoutMs) {
                if (AppLauncher.isRunning(appId))
                    AppLauncher.stop(appId);
                root.releaseTarget(appId);
                root.failApp(appId, "The launch did not produce a matching game window before the timeout.");
            }
        }
    }

    function drainQueue() {
        var ids = Object.keys(root.queuedIds);
        for (var i = 0; i < ids.length; ++i) {
            var appId = ids[i];
            var app = AppRegistry.byId(appId);
            if (!app) {
                root.queuedIds = root.clearObjectKey(root.queuedIds, appId);
                continue;
            }
            if (root.windowsFor(app).length > 0 || appId in root.launchTargets || AppLauncher.isRunning(appId)) {
                root.queuedIds = root.clearObjectKey(root.queuedIds, appId);
                continue;
            }
            var workspace = root.emptyWorkspaceFor(app);
            if (!workspace)
                continue;
            // Launch only after a workspace was found and reserved; the reservation
            // prevents another queued game from claiming it in this same poll.
            root.beginLaunch(app, workspace);
        }
    }

    function reconcileStops() {
        var ids = Object.keys(root.stoppingIds);
        for (var i = 0; i < ids.length; ++i) {
            var appId = ids[i];
            var app = AppRegistry.byId(appId);
            var stillHasWindow = app && root.windowsFor(app).length > 0;
            if (!stillHasWindow && !AppLauncher.isRunning(appId)) {
                root.stoppingIds = root.clearObjectKey(root.stoppingIds, appId);
            } else if (Date.now() - Number(root.stoppingIds[appId] || 0) > root.stopTimeoutMs) {
                root.stoppingIds = root.clearObjectKey(root.stoppingIds, appId);
                root.failApp(appId, "The game is still running after the close request. Use the game's own exit or a separate force-stop action.");
            }
        }
    }

    Timer {
        id: queueWatcher
        interval: root.queuePollMs
        repeat: true
        running: Object.keys(root.queuedIds).length > 0
            || Object.keys(root.launchTargets).length > 0
            || Object.keys(root.stoppingIds).length > 0
        onTriggered: {
            Hyprland.refreshWorkspaces();
            Hyprland.refreshToplevels();
            root.reconcileLaunchTargets();
            root.drainQueue();
            root.reconcileStops();
        }
    }
}
