pragma Singleton
import QtQuick
import Quickshell

Singleton {
    id: root

    readonly property string configDir: Quickshell.env("XDG_CONFIG_HOME") || ((Quickshell.env("HOME") || "") + "/.config")
    readonly property string prefixHelper: root.configDir + "/hypr/scripts/ricelin-prefix"

    function runManagedAction(action, app, destination) {
        var prefix = app && app.prefix ? String(app.prefix) : "";
        if (!prefix)
            return false;

        var runner = app && app.runner ? String(app.runner) : "wine";
        var executable = app && app.executable ? String(app.executable) : "";
        var workingDirectory = app && app.workingDirectory ? String(app.workingDirectory) : "";
        var command = ["sh", root.prefixHelper, action];

        if (action === "clone") {
            if (!destination)
                return false;
            command.push(prefix, String(destination), runner, executable, workingDirectory);
        } else {
            command.push(prefix, runner, executable, workingDirectory);
        }

        Quickshell.execDetached(command);
        return true;
    }

    function create(app) {
        return root.runManagedAction("create", app, "");
    }

    function openFiles(app) {
        return root.runManagedAction("open", app, "");
    }

    function winetricks(app) {
        return root.runManagedAction("winetricks", app, "");
    }

    function clone(app, destPath) {
        return root.runManagedAction("clone", app, destPath);
    }

    function reset(app) {
        return root.runManagedAction("reset", app, "");
    }

    function remove(app) {
        return root.runManagedAction("remove", app, "");
    }
}
