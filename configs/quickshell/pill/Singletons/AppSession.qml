pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland
import "../lib/blades.js" as Blades
import "../lib/desktopentry.js" as DesktopImport
import "../lib/appstate.js" as AppState

/*
 * Shared live application session used by both Blades and Apps/detail.
 *
 * AppLauncher remains the process executor; this singleton owns window
 * identity, existing-window activation, app-facing state, and stop requests.
 * BladeLauncherModel still owns its monitor-specific empty-workspace policy.
 */
Singleton {
    id: root

    readonly property int launchTimeoutMs: 90000
    readonly property int stopTimeoutMs: 15000
    property var launchRequests: ({}) // appId -> { requestedAt, monitor, bladeManaged }

    readonly property var windows: {
        var tl = (Hyprland.toplevels && Hyprland.toplevels.values) || [];
        var out = [];
        for (var i = 0; i < tl.length; ++i) {
            var t = tl[i];
            if (!t)
                continue;
            var ipc = t.lastIpcObject;
            var workspace = t.workspace;
            var cls = ipc && ipc.class ? ipc.class
                : (t.wayland && t.wayland.appId ? t.wayland.appId : "");
            out.push({
                address: Dock.hex(t.address),
                cls: cls,
                title: t.title || (ipc && ipc.title ? ipc.title : ""),
                workspace: workspace ? String(workspace.name || "") : "",
                workspaceId: workspace ? Number(workspace.id || 0) : 0,
                monitor: workspace && workspace.monitor ? String(workspace.monitor.name || "") : "",
                pid: Number((ipc && ipc.pid) || t.pid || 0)
            });
        }
        return out;
    }

    function desktopFor(app) {
        if (!app || AppLauncher.effectiveRunnerFor(app) !== "native")
            return null;
        // findEntry only accepts records whose declared runner is "native".
        // Auto can resolve to native, so normalize the copy before looking up.
        var nativeApp = Object.assign({}, app, { runner: "native" });
        return DesktopImport.findEntry(DesktopEntries.applications.values || [], nativeApp);
    }

    function windowsFor(app) {
        if (!app)
            return [];
        var entry = root.desktopFor(app);
        var out = [];
        var src = root.windows;
        for (var i = 0; i < src.length; ++i) {
            if (Blades.matchesWindow(app, src[i], entry))
                out.push(src[i]);
        }
        return out;
    }

    function isActive(appId) {
        var app = AppRegistry.byId(appId);
        return AppLauncher.isRunning(appId) || (!!app && root.windowsFor(app).length > 0);
    }

    function isBusy(appId) {
        return root.isActive(appId) || AppLauncher.isPending(appId)
            || (appId in root.launchRequests)
            || (appId in BladeSession.queuedIds)
            || (appId in BladeSession.launchTargets);
    }

    function clearObjectKey(object, key) {
        var next = Object.assign({}, object || {});
        delete next[key];
        return next;
    }

    function clearLaunchRequest(appId) {
        if (!(appId in root.launchRequests))
            return;
        root.launchRequests = root.clearObjectKey(root.launchRequests, appId);
    }

    function releaseTarget(appId) {
        var target = BladeSession.launchTargets[appId];
        if (target && target.key && BladeSession.reservedWorkspaces[target.key] === appId)
            BladeSession.reservedWorkspaces = root.clearObjectKey(BladeSession.reservedWorkspaces, target.key);
        if (target)
            BladeSession.launchTargets = root.clearObjectKey(BladeSession.launchTargets, appId);
    }

    /** Focus/cycle an existing app window instead of dispatching a duplicate launch. */
    function activateExisting(appId, preferredMonitor) {
        var app = AppRegistry.byId(appId);
        if (!app)
            return false;
        var matches = root.windowsFor(app);
        if (matches.length === 0)
            return false;
        var active = Hyprland.activeToplevel;
        var activeAddress = active && active.address ? Dock.hex(active.address) : "";
        var target = Blades.nextWindow(matches, activeAddress);
        if (target)
            Dock.focusWindow(target, String(preferredMonitor || target.monitor || ""));
        root.clearLaunchRequest(appId);
        BladeSession.failedIds = root.clearObjectKey(BladeSession.failedIds, appId);
        return true;
    }

    /*
     * The common launch request path. Blades passes beforeStart to preserve
     * workspace reservation/revalidation; the Apps surface uses the same path
     * without a workspace callback. Repeated clicks focus a live window or are
     * rejected while work for that app is already in flight.
     */
    function launch(appId, useGameMode, beforeStart) {
        var id = String(appId || "");
        var app = AppRegistry.byId(id);
        if (!app)
            return false;
        if (useGameMode === undefined)
            useGameMode = true;

        if (root.activateExisting(id))
            return true;
        if (AppLauncher.isPending(id) || AppLauncher.isRunning(id))
            return false;
        var bladeManaged = typeof beforeStart === "function";
        if (!bladeManaged && (id in BladeSession.queuedIds || id in BladeSession.launchTargets))
            return false;
        if (id in root.launchRequests)
            return false;

        var accepted = AppLauncher.launch(id, useGameMode, beforeStart);
        if (!accepted)
            return false;
        BladeSession.failedIds = root.clearObjectKey(BladeSession.failedIds, id);
        root.launchRequests = Object.assign({}, root.launchRequests, {
            [id]: { requestedAt: Date.now(), monitor: "", bladeManaged: bladeManaged }
        });
        return true;
    }

    /** Request a graceful stop and close any matching windows through Hyprland. */
    function stop(appId, monitor) {
        var id = String(appId || "");
        var app = AppRegistry.byId(id);
        if (!app)
            return false;

        if (id in BladeSession.queuedIds)
            BladeSession.queuedIds = root.clearObjectKey(BladeSession.queuedIds, id);
        if (AppLauncher.isPending(id))
            AppLauncher.cancelPending(id);

        var matches = root.windowsFor(app);
        var tracked = AppLauncher.isRunning(id);
        var hasTarget = id in BladeSession.launchTargets;
        if (matches.length === 0 && !tracked && !hasTarget) {
            root.clearLaunchRequest(id);
            BladeSession.failedIds = root.clearObjectKey(BladeSession.failedIds, id);
            return false;
        }

        BladeSession.stoppingIds = Object.assign({}, BladeSession.stoppingIds, {
            [id]: { requestedAt: Date.now(), monitor: String(monitor || "") }
        });
        root.clearLaunchRequest(id);
        for (var i = 0; i < matches.length; ++i) {
            var address = Dock.hex(matches[i].address);
            if (address.length > 0)
                Hyprland.dispatch('hl.dsp.window.close({window="address:' + address + '"})');
        }
        if (tracked)
            AppLauncher.stop(id);
        // Releasing the reservation is safe: a still-open window makes its
        // workspace ineligible until Hyprland reports that it has closed.
        root.releaseTarget(id);
        BladeSession.queuedIds = root.clearObjectKey(BladeSession.queuedIds, id);
        BladeSession.failedIds = root.clearObjectKey(BladeSession.failedIds, id);
        return true;
    }

    function forceStop(appId) {
        var id = String(appId || "");
        var app = AppRegistry.byId(id);
        root.clearLaunchRequest(id);
        var matches = app ? root.windowsFor(app) : [];
        for (var i = 0; i < matches.length; ++i) {
            var pid = Number(matches[i].pid || 0);
            var address = Dock.hex(matches[i].address);
            if (pid > 1)
                Quickshell.execDetached(["kill", "-KILL", String(pid)]);
            else if (address.length > 0)
                Hyprland.dispatch('hl.dsp.window.close({window="address:' + address + '"})');
        }
        if (AppLauncher.isRunning(id) || !app)
            AppLauncher.forceStop(id);
        root.releaseTarget(id);
        BladeSession.queuedIds = root.clearObjectKey(BladeSession.queuedIds, id);
        BladeSession.failedIds = root.clearObjectKey(BladeSession.failedIds, id);
    }

    function stateFor(appId) {
        var id = String(appId || "");
        var app = AppRegistry.byId(id);
        if (!app)
            return AppState.deriveState({ exists: false });
        return AppState.deriveState({
            exists: true,
            stopping: id in BladeSession.stoppingIds,
            failed: id in BladeSession.failedIds || AppLauncher.failureFor(id).length > 0,
            windowCount: root.windowsFor(app).length,
            folderMissing: !!app.folderMissing,
            needsSetup: !!app.needsSetup,
            targetValid: AppLauncher.hasLaunchTarget(app),
            pending: AppLauncher.isPending(id),
            launching: (id in root.launchRequests) || (id in BladeSession.launchTargets) || AppLauncher.isRunning(id),
            waiting: id in BladeSession.queuedIds,
            processRunning: AppLauncher.isRunning(id)
        });
    }

    function reconcile() {
        var requests = Object.assign({}, root.launchRequests);
        var now = Date.now();
        for (var id in requests) {
            var req = requests[id];
            var app = AppRegistry.byId(id);
            if (!app || root.windowsFor(app).length > 0) {
                delete requests[id];
                continue;
            }
            if (now - Number(req.requestedAt || 0) > root.launchTimeoutMs
                    && !AppLauncher.isPending(id) && !AppLauncher.isRunning(id)) {
                delete requests[id];
                if (!req.bladeManaged) {
                    var message = "The launch did not produce a matching application window before the timeout.";
                    AppLauncher.setFailure(id, message);
                    Quickshell.execDetached(["notify-send", "-u", "normal", "-a", "Ricelin", "Launch timed out: " + app.name, message]);
                }
            }
        }
        if (JSON.stringify(requests) !== JSON.stringify(root.launchRequests))
            root.launchRequests = requests;

        var stops = Object.assign({}, BladeSession.stoppingIds);
        for (var stopId in stops) {
            var stopState = stops[stopId];
            var stopAt = typeof stopState === "object" ? Number(stopState.requestedAt || 0) : Number(stopState || 0);
            var stopApp = AppRegistry.byId(stopId);
            var stillHasWindow = !!stopApp && root.windowsFor(stopApp).length > 0;
            if (!stillHasWindow && !AppLauncher.isRunning(stopId)) {
                delete stops[stopId];
            } else if (now - stopAt > root.stopTimeoutMs) {
                delete stops[stopId];
                AppLauncher.setFailure(stopId, "The application is still running after a close request.");
            }
        }
        if (JSON.stringify(stops) !== JSON.stringify(BladeSession.stoppingIds))
            BladeSession.stoppingIds = stops;
    }

    Timer {
        interval: 800
        repeat: true
        running: Object.keys(root.launchRequests).length > 0 || Object.keys(BladeSession.stoppingIds).length > 0
        onTriggered: root.reconcile()
    }

    Connections {
        target: AppLauncher
        function onLaunchDeferred(appId, message) {
            root.clearLaunchRequest(String(appId));
        }
        function onPreparationFailed(appId, message) {
            root.clearLaunchRequest(String(appId));
        }
        function onLaunchFailed(appId, message) {
            root.clearLaunchRequest(String(appId));
        }
    }
}
