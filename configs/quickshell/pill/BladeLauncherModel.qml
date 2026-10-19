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
        if (app.id in BladeSession.stoppingIds)
            return "stopping";
        if (app.id in BladeSession.failedIds)
            return "failed";
        if (root.windowsFor(app).length > 0)
            return "running";
        if (app.folderMissing)
            return "missing";
        if (app.needsSetup || !app.executable)
            return "setup";
        if (AppLauncher.isPending(app.id))
            return "preparing";
        if (app.id in BladeSession.launchTargets)
            return "launching";
        if (app.id in BladeSession.queuedIds)
            return "waiting";
        if (AppLauncher.isRunning(app.id))
            return "launching";
        return "idle";
    }

    function labelFor(index) {
        var app = root.appAt(index);
        return app ? RuntimeManager.profileFor(AppLauncher.effectiveRunnerFor(app)).shortLabel : "";
    }

    function monitorExists(name) {
        if (!name)
            return false;
        var monitors = Hyprland.monitors.values || [];
        for (var i = 0; i < monitors.length; ++i)
            if (monitors[i] && String(monitors[i].name || "") === String(name))
                return true;
        return false;
    }

    function configuredMonitorFor(app) {
        var configured = app && app.window ? String(app.window.monitor || "") : "";
        if (configured.length > 0 && configured.toLowerCase() !== "automatic" && configured.toLowerCase() !== "auto")
            return configured;
        return "";
    }

    function targetMonitorFor(app) {
        var configured = root.configuredMonitorFor(app);
        if (configured && root.monitorExists(configured))
            return configured;
        if (root.screenName && root.monitorExists(root.screenName))
            return root.screenName;
        var focused = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "";
        return root.monitorExists(focused) ? focused : "";
    }

    function notifyMonitorFallback(app) {
        var configured = root.configuredMonitorFor(app);
        if (!configured || root.monitorExists(configured) || app.id in BladeSession.monitorFallbackNotified)
            return;
        var fallback = root.targetMonitorFor(app);
        BladeSession.monitorFallbackNotified = Object.assign({}, BladeSession.monitorFallbackNotified, { [app.id]: true });
        Quickshell.execDetached(["notify-send", "-u", "normal", "-a", "Ricelin",
            "Game monitor unavailable", app.name + " was configured for " + configured
                + ", which is not connected. Waiting on " + (fallback || "a connected monitor") + " instead."]);
    }

    function emptyWorkspaceFor(app) {
        return Blades.chooseEmptyWorkspace(
            root.workspaces,
            root.windows,
            BladeSession.reservedWorkspaces,
            root.targetMonitorFor(app)
        );
    }

    function clearObjectKey(object, key) {
        var next = Object.assign({}, object || {});
        delete next[key];
        return next;
    }

    function releaseTarget(appId) {
        var target = BladeSession.launchTargets[appId];
        if (target) {
            BladeSession.reservedWorkspaces = root.clearObjectKey(BladeSession.reservedWorkspaces, target.key);
            BladeSession.launchTargets = root.clearObjectKey(BladeSession.launchTargets, appId);
        }
    }

    function failApp(appId, reason) {
        BladeSession.failedIds = Object.assign({}, BladeSession.failedIds, { [appId]: String(reason) });
    }

    function beginLaunch(app, workspace) {
        if (!app || !workspace || !Number(workspace.id) || Number(workspace.id) <= 0)
            return false;

        var key = Blades.workspaceKey(workspace);
        if (!key || BladeSession.reservedWorkspaces[key])
            return false;

        var target = {
            workspaceId: Number(workspace.id),
            workspaceName: String(workspace.name || workspace.id),
            monitor: String(workspace.monitor || root.screenName),
            key: key,
            startedAt: Date.now()
        };

        BladeSession.failedIds = root.clearObjectKey(BladeSession.failedIds, app.id);
        BladeSession.queuedIds = root.clearObjectKey(BladeSession.queuedIds, app.id);
        BladeSession.reservedWorkspaces = Object.assign({}, BladeSession.reservedWorkspaces, { [key]: app.id });
        BladeSession.launchTargets = Object.assign({}, BladeSession.launchTargets, { [app.id]: target });

        // Prefix setup may take several seconds. Keep the workspace reserved
        // but don't focus it until the setup callback, then re-check occupancy
        // immediately before the game process starts.
        if (!AppLauncher.launch(app.id, true, function() {
            Hyprland.refreshWorkspaces();
            Hyprland.refreshToplevels();
            var now = root.windows;
            for (var i = 0; i < now.length; ++i) {
                var w = now[i];
                if (Number(w.workspaceId || 0) === target.workspaceId
                        || String(w.workspace || "") === target.workspaceName)
                    return false;
            }
            Hyprland.dispatch("hl.dsp.focus({ workspace = " + Number(target.workspaceId) + " })");
            return true;
        })) {
            root.releaseTarget(app.id);
            // A synchronous preflight deferral has already moved this game back
            // to the queue through onLaunchDeferred; don't mask that state as a
            // launch failure.
            if (app.id in BladeSession.queuedIds)
                return false;
            if (AppLauncher.isPending(app.id))
                root.failApp(app.id, "The game launch is already being prepared.");
            else
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
            BladeSession.failedIds = root.clearObjectKey(BladeSession.failedIds, current.id);
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
            BladeSession.failedIds = root.clearObjectKey(BladeSession.failedIds, app.id);
            return;
        }

        if (app.id in BladeSession.queuedIds || app.id in BladeSession.launchTargets || AppLauncher.isRunning(app.id))
            return;

        BladeSession.failedIds = root.clearObjectKey(BladeSession.failedIds, app.id);
        root.notifyMonitorFallback(app);
        var workspace = root.emptyWorkspaceFor(app);
        if (!workspace) {
            // Queue intent only. No process, Wine prefix, or Steam launch starts
            // until a usable empty workspace is found.
            BladeSession.queuedIds = Object.assign({}, BladeSession.queuedIds, {
                [app.id]: { requestedAt: Date.now(), monitor: root.targetMonitorFor(app) }
            });
            return;
        }

        root.beginLaunch(app, workspace);
    }

    function markStopping(app, monitor) {
        BladeSession.stoppingIds = Object.assign({}, BladeSession.stoppingIds, {
            [app.id]: { requestedAt: Date.now(), monitor: String(monitor || root.targetMonitorFor(app) || "") }
        });
    }

    function stop(index) {
        var app = root.appAt(index);
        if (!app)
            return;

        // Double-clicking a queued game cancels it. It never launches later
        // without the user asking again.
        if (app.id in BladeSession.queuedIds) {
            BladeSession.queuedIds = root.clearObjectKey(BladeSession.queuedIds, app.id);
            BladeSession.failedIds = root.clearObjectKey(BladeSession.failedIds, app.id);
            return;
        }

        // If the prefix preparation process is still running, invalidate the
        // continuation token. The safe helper may finish initializing the prefix,
        // but the game's launch continuation is cancelled.
        if (AppLauncher.isPending(app.id)) {
            AppLauncher.cancelPending(app.id);
            root.releaseTarget(app.id);
            BladeSession.stoppingIds = root.clearObjectKey(BladeSession.stoppingIds, app.id);
            BladeSession.failedIds = root.clearObjectKey(BladeSession.failedIds, app.id);
            return;
        }

        var existing = root.windowsFor(app);
        if (existing.length > 0) {
            root.markStopping(app, existing[0].monitor || root.targetMonitorFor(app));
            for (var i = 0; i < existing.length; ++i) {
                var address = Dock.hex(existing[i].address);
                if (address.length > 0)
                    Hyprland.dispatch('hl.dsp.window.close({window="address:' + address + '"})');
            }
            return;
        }

        if (app.id in BladeSession.launchTargets) {
            if (AppLauncher.isRunning(app.id)) {
                root.markStopping(app, BladeSession.launchTargets[app.id].monitor);
                AppLauncher.stop(app.id);
            } else {
                root.releaseTarget(app.id);
                BladeSession.failedIds = root.clearObjectKey(BladeSession.failedIds, app.id);
            }
            return;
        }

        if (AppLauncher.isRunning(app.id)) {
            root.markStopping(app, root.targetMonitorFor(app));
            AppLauncher.stop(app.id);
            return;
        }

        BladeSession.failedIds = root.clearObjectKey(BladeSession.failedIds, app.id);
    }

    function reconcileLaunchTargets() {
        var ids = Object.keys(BladeSession.launchTargets);
        for (var i = 0; i < ids.length; ++i) {
            var appId = ids[i];
            var target = BladeSession.launchTargets[appId];
            if (target.monitor && root.screenName && target.monitor !== root.screenName)
                continue;
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
                BladeSession.stoppingIds = root.clearObjectKey(BladeSession.stoppingIds, appId);
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
        var ids = Object.keys(BladeSession.queuedIds);
        for (var i = 0; i < ids.length; ++i) {
            var appId = ids[i];
            var queued = BladeSession.queuedIds[appId];
            if (queued && queued.monitor && root.screenName && queued.monitor !== root.screenName)
                continue;
            var app = AppRegistry.byId(appId);
            if (!app) {
                BladeSession.queuedIds = root.clearObjectKey(BladeSession.queuedIds, appId);
                continue;
            }
            if (root.windowsFor(app).length > 0 || appId in BladeSession.launchTargets || AppLauncher.isRunning(appId)) {
                BladeSession.queuedIds = root.clearObjectKey(BladeSession.queuedIds, appId);
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
        var ids = Object.keys(BladeSession.stoppingIds);
        for (var i = 0; i < ids.length; ++i) {
            var appId = ids[i];
            var stopState = BladeSession.stoppingIds[appId];
            if (!stopState)
                continue;
            if (stopState.monitor && root.screenName && stopState.monitor !== root.screenName)
                continue;
            var requestedAt = typeof stopState === "object"
                ? Number(stopState.requestedAt || 0) : Number(stopState || 0);
            var app = AppRegistry.byId(appId);
            var stillHasWindow = app && root.windowsFor(app).length > 0;
            if (!stillHasWindow && !AppLauncher.isRunning(appId)) {
                BladeSession.stoppingIds = root.clearObjectKey(BladeSession.stoppingIds, appId);
            } else if (Date.now() - requestedAt > root.stopTimeoutMs) {
                BladeSession.stoppingIds = root.clearObjectKey(BladeSession.stoppingIds, appId);
                root.failApp(appId, "The game is still running after the close request. Use the game's own exit or a separate force-stop action.");
            }
        }
    }

    Connections {
        target: AppLauncher
        function onLaunchDeferred(appId, message) {
            var id = String(appId);
            root.releaseTarget(id);
            BladeSession.queuedIds = Object.assign({}, BladeSession.queuedIds, {
                [id]: { requestedAt: Date.now(), monitor: root.targetMonitorFor(AppRegistry.byId(id)) }
            });
        }
        function onPreparationFailed(appId, message) {
            root.releaseTarget(String(appId));
            BladeSession.queuedIds = root.clearObjectKey(BladeSession.queuedIds, String(appId));
            root.failApp(String(appId), "Prefix preparation failed: " + String(message || "unknown error"));
        }
        function onLaunchFailed(appId, message) {
            root.releaseTarget(String(appId));
            BladeSession.queuedIds = root.clearObjectKey(BladeSession.queuedIds, String(appId));
            root.failApp(String(appId), String(message || "The launch exited before it produced a game window."));
        }
    }

    function hasOwnedPendingWork() {
        var queues = BladeSession.queuedIds;
        for (var q in queues)
            if (!queues[q].monitor || !root.screenName || queues[q].monitor === root.screenName)
                return true;

        var targets = BladeSession.launchTargets;
        for (var t in targets)
            if (!targets[t].monitor || !root.screenName || targets[t].monitor === root.screenName)
                return true;

        var stops = BladeSession.stoppingIds;
        for (var s in stops)
            if (!stops[s].monitor || !root.screenName || stops[s].monitor === root.screenName)
                return true;
        return false;
    }

    Timer {
        id: queueWatcher
        interval: root.queuePollMs
        repeat: true
        running: root.hasOwnedPendingWork()
        onTriggered: {
            Hyprland.refreshWorkspaces();
            Hyprland.refreshToplevels();
            root.reconcileLaunchTargets();
            root.drainQueue();
            root.reconcileStops();
        }
    }
}
