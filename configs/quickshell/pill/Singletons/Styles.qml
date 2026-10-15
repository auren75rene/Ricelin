pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * The styles the pill can switch between: extra Quickshell setups such as
 * Persona, listed and started by configs/hypr/scripts/ricelin-style. This file
 * only asks that script for the list and tells it what to do; where styles come
 * from, and how an instance is started and found again, is the script's job.
 *
 * `list` holds { id, name, note, running } records. It is replaced wholesale on
 * every refresh, never edited in place, so every binding on it updates.
 */
Singleton {
    id: root

    property var list: []
    property bool busy: false
    property string pendingAction: ""

    signal registrationFinished(bool succeeded)

    readonly property string script: Quickshell.env("HOME") + "/.config/hypr/scripts/ricelin-style"

    /** Id of the running style, or "ricelin" when none runs. */
    readonly property string active: {
        for (var i = 0; i < root.list.length; i++)
            if (root.list[i].running)
                return root.list[i].id;
        return "ricelin";
    }

    /** One tab-separated line per style: id, name, state, note. */
    function parse(text) {
        var out = [];
        var lines = String(text).split("\n");
        for (var i = 0; i < lines.length; i++) {
            var f = lines[i].split("\t");
            if (f.length < 3 || f[0].length === 0)
                continue;
            out.push({ id: f[0], name: f[1] || f[0], running: f[2] === "running", note: f.length > 3 ? f[3] : "" });
        }
        return out;
    }

    function refresh() {
        if (!listProc.running)
            listProc.running = true;
    }

    /** Switch to a style, or back to plain Ricelin if it is the one already running. */
    function choose(id) {
        if (root.busy)
            return;
        if (id === "ricelin" || id === root.active)
            root.run(["off"]);
        else
            root.run(["switch", id]);
    }

    function run(args) {
        root.busy = true;
        actProc.command = [root.script].concat(args);
        actProc.running = true;
    }

    /** Register an external Quickshell setup using ricelin-style's validated CLI. */
    function registerStyle(id, name, kind, target, note) {
        if (root.busy)
            return;
        root.pendingAction = "register";
        root.run(["add", id, name, kind, target, note || ""]);
    }

    Process {
        id: listProc
        command: [root.script, "list"]
        stdout: StdioCollector {
            onStreamFinished: root.list = root.parse(this.text)
        }
    }

    Process {
        id: actProc
        onExited: (exitCode, exitStatus) => {
            root.busy = false;
            if (root.pendingAction === "register")
                root.registrationFinished(exitCode === 0);
            root.pendingAction = "";
            // A new instance takes a moment to show up as running; registrations
            // also refresh the index after the script has written its .conf file.
            settle.restart();
        }
    }

    Timer {
        id: settle
        interval: 800
        onTriggered: root.refresh()
    }
}
