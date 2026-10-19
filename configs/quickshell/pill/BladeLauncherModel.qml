pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import "Singletons"
import "lib/blades.js" as Blades

/**
 * What the blade fan shows: the games and Wine apps in the app registry.
 *
 * Which records qualify, and their order, is decided by lib/blades.js (games
 * and Wine-family runners by default, a per-app Auto / Pin / Hide override). No
 * app is named here, so a stale entry is hidden from the app's own editor
 * rather than by editing code. Installed desktop entries are not listed on
 * their own: add one through the Add or Scan sheet and it is a registry record
 * like any other.
 *
 * A native record whose desktop entry can be found is launched through that
 * entry, never rebuilt from Exec=, which may carry %u placeholders, env
 * assignments or Flatpak wrappers. Existing windows are activated through the
 * same focus/restore path as the dock rather than attempting a second launch.
 */
QtObject {
    id: root

    readonly property int maxVisible: 6
    /** Screen receiving clicks, needed when restoring a minimized window. */
    property string screenName: ""

    /** Id of the app that was just launched; shows as "starting" for a moment. */
    property string launchingId: ""

    /** A small, plain-object view of Hyprland clients for matching and tests. */
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
                workspace: t.workspace ? t.workspace.name : ""
            });
        }
        return out;
    }

    function desktopFor(app) {
        if (!app || app.runner !== "native")
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

    /** Launchable records in blade order, capped at maxVisible. */
    readonly property var apps: {
        var picked = Blades.select(AppRegistry.apps, 0);
        var out = [];
        for (var i = 0; i < picked.length && out.length < root.maxVisible; ++i) {
            var app = picked[i];
            if (app.runner !== "native") {
                out.push(app);
                continue;
            }
            var entry = root.desktopFor(app);
            if (entry)
                out.push(Object.assign({}, app, { desktopEntry: entry }));
            else if (app.executable)
                out.push(app);
        }
        return out;
    }

    readonly property int count: root.apps.length

    function appAt(index) {
        return index >= 0 && index < root.apps.length ? root.apps[index] : null;
    }

    /** "idle", "launching" or "running", using live windows as well as managed processes. */
    function stateFor(index) {
        var app = root.appAt(index);
        if (!app)
            return "idle";
        if (root.windowsFor(app).length > 0)
            return "running";
        if (root.launchingId === app.id)
            return "launching";
        return AppLauncher.isRunning(app.id) ? "running" : "idle";
    }

    /** What the app runs on, for the line under its name. */
    function labelFor(index) {
        var app = root.appAt(index);
        return app ? RuntimeManager.profileFor(app.runner).shortLabel : "";
    }

    /*
     * A blade is a navigation action, not a blind "spawn another copy" button:
     * activate/cycle an existing app window (including restoring a minimized
     * one), otherwise use AppLauncher. If the process is already starting but
     * hasn't mapped a window yet, don't launch a duplicate.
     */
    function launch(index) {
        var app = root.appAt(index);
        if (!app)
            return;

        var existing = root.windowsFor(app);
        if (existing.length > 0) {
            var active = Hyprland.activeToplevel;
            var activeAddress = active && active.address ? Dock.hex(active.address) : "";
            var target = Blades.nextWindow(existing, activeAddress);
            if (target)
                Dock.focusWindow(target, root.screenName);
            root.launchingId = "";
            launchFeedback.stop();
            return;
        }

        if (AppLauncher.isRunning(app.id)) {
            root.launchingId = app.id;
            launchFeedback.restart();
            return;
        }

        root.launchingId = app.id;
        launchFeedback.restart();
        AppLauncher.launch(app.id, false);
    }

    property Timer launchFeedback: Timer {
        interval: 1800
        onTriggered: root.launchingId = ""
    }
}
