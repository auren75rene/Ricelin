pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string configDir: Quickshell.env("XDG_CONFIG_HOME") || ((Quickshell.env("HOME") || "") + "/.config")
    readonly property string prefixHelper: root.configDir + "/hypr/scripts/ricelin-prefix"
    property var knownPrefixes: []

    function refreshPrefixes() {
        if (!prefixScanProc.running)
            prefixScanProc.running = true
    }

    function prefixOptions(currentPath) {
        var current = String(currentPath || "")
        var options = []
        var foundCurrent = false
        for (var i = 0; i < root.knownPrefixes.length; ++i) {
            var item = root.knownPrefixes[i]
            if (String(item.path || "") === current) {
                options.push(item)
                foundCurrent = true
                break
            }
        }
        if (current.length > 0 && !foundCurrent) {
            var bits = current.split("/")
            var name = bits[bits.length - 1] || current
            options.push({ name: name, path: current, label: "Current/custom — " + current, managed: false, kind: "current" })
        }
        for (var j = 0; j < root.knownPrefixes.length; ++j) {
            var candidate = root.knownPrefixes[j]
            if (String(candidate.path || "") !== current)
                options.push(candidate)
        }
        return options
    }

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


    /**
     * Idempotent preparation used by first launch. A successful callback means
     * the selected runner's prefix path is ready; arbitrary existing folders
     * are rejected by ricelin-prefix rather than overwritten.
     */
    function ensurePrefix(app, callback) {
        var done = typeof callback === "function" ? callback : function() {};
        if (!app) {
            done(false, "No game configuration was supplied.");
            return false;
        }

        var runner = String(app.runner || "");
        if (runner === "native" || runner === "steam") {
            done(true, "");
            return true;
        }
        if (["wine", "wine-staging", "umu"].indexOf(runner) < 0) {
            done(false, "No compatible Windows-game runner was selected.");
            return false;
        }

        var prefix = String(app.prefix || "");
        if (!prefix) {
            done(false, "This game has no dedicated prefix path configured.");
            return false;
        }

        var command = ["sh", root.prefixHelper, "ensure", prefix, runner,
            String(app.executable || ""), String(app.workingDirectory || "")];
        var proc = ensureProcComponent.createObject(root, {
            command: command,
            finishedCallback: done,
            running: true
        });
        if (!proc) {
            done(false, "Could not create the prefix preparation process.");
            return false;
        }
        return true;
    }

    Component {
        id: ensureProcComponent
        Process {
            id: ensureProc
            property var finishedCallback: null
            stderr: StdioCollector { id: ensureStderr }
            stdout: StdioCollector { id: ensureStdout }
            onExited: function(exitCode) {
                var message = String(ensureStderr.text || ensureStdout.text || "").trim();
                var callback = ensureProc.finishedCallback;
                ensureProc.finishedCallback = null;
                if (callback)
                    callback(exitCode === 0, message);
                ensureProc.destroy();
            }
        }
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

    Component.onCompleted: root.refreshPrefixes()

    Process {
        id: prefixScanProc
        command: ["sh", root.prefixHelper, "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var result = JSON.parse(String(this.text || "[]"))
                    root.knownPrefixes = Array.isArray(result) ? result : []
                } catch (e) {
                    root.knownPrefixes = []
                    console.warn("Ricelin: could not parse the prefix inventory:", String(e))
                }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                var message = String(this.text || "").trim()
                if (message.length > 0)
                    console.warn("Ricelin prefix inventory:", message)
            }
        }
        onExited: function(exitCode) {
            if (exitCode !== 0)
                console.warn("Ricelin: prefix inventory exited with status", exitCode)
        }
    }
}
