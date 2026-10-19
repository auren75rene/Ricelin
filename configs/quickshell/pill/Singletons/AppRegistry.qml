pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "AppRegistryStore.js" as RegistryStore

/**
 * Application Registry: the single source of truth for every non-native app
 * Ricelin knows how to launch — games today, dev/engineering/utility tools
 * later. The Games surface is a filtered *view* over this list, not a
 * subsystem of its own, so a new category never needs new plumbing.
 *
 * Each entry is a plain JSON object (see `template()` below for the full
 * shape); the registry itself is agnostic about what "runner" means, that
 * belongs to RuntimeManager and AppLauncher. Persisted as one JSON array —
 * same raw FileView + JSON.parse/stringify approach as Launcher's usage
 * store, chosen over JsonAdapter because JsonAdapter's typed schema doesn't
 * fit a free-form, growable list of heterogeneous app records.
 *
 * Writes are debounced through `persist()` and always replace `apps` with a
 * new array (never mutate in place) so every binding and Repeater downstream
 * re-evaluates reliably — QML's var properties don't notify on in-place
 * array/object mutation.
 */
Singleton {
    id: root

    property bool ready: false
    property var apps: []
    property string loadError: ""
    property bool recovering: false
    property bool recoveryWritePending: false
    property string recoveryBackupPath: ""
    property string recoveryStatus: ""

    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || ((Quickshell.env("HOME") || "") + "/.config")
    readonly property string dataHome: Quickshell.env("XDG_DATA_HOME") || ((Quickshell.env("HOME") || "") + "/.local/share")
    readonly property string dir: root.configHome + "/ricelin"
    readonly property string path: root.dir + "/applications.json"
    readonly property string gamesDirectory: Quickshell.env("RICELIN_GAMES_DIR") || ((Quickshell.env("HOME") || "") + "/Games")
    readonly property string gamesScanner: root.configHome + "/hypr/scripts/ricelin-games-scan"

    readonly property var categories: [
        { id: "game", label: "Games", glyph: "gamepad" },
        { id: "development", label: "Development", glyph: "keyboard" },
        { id: "engineering", label: "Engineering", glyph: "layers" },
        { id: "utility", label: "Utilities", glyph: "cog" }
    ]

    function categoryLabel(id) {
        for (var i = 0; i < root.categories.length; i++)
            if (root.categories[i].id === id)
                return root.categories[i].label;
        return id;
    }

    /** Every field an app record can carry. Spread this and override rather than hand-rolling a literal, so a later field addition only has to happen here. */
    function template() {
        return {
            id: "",
            name: "",
            category: "game",
            favorite: false,
            blade: "auto",
            bladeOrder: 0,
            iconImage: "",
            runner: "auto",
            executable: "",
            sourcePath: "",
            gameFolder: "",
            candidateExecutables: [],
            needsSetup: false,
            discovered: false,
            folderMissing: false,
            desktopEntryId: "",
            workingDirectory: "",
            prefix: "",
            umuId: "",
            steamAppId: "",
            protonBuild: "GE-Proton",
            graphicsApi: "unknown",
            args: [],
            env: ({}),
            dllOverrides: ({}),
            window: { mode: "windowed", monitor: "", resolution: "native" },
            performance: { mangohud: false, gamescope: false, fpsLimit: 0 },
            createdAt: 0,
            lastLaunched: 0,
            launchCount: 0,
            runtime: { provider: "auto", variant: "", version: "", build: "" },
            environment: { type: "wineprefix", path: "", name: "", arch: "win64" }
        };
    }

    /**
     * `runner` and `prefix` are the actual source of truth — AppLauncher
     * only ever reads those two. `runtime` and `environment` below are
     * *derived* from them, one direction only, for a future richer display
     * (a name, an arch, a variant). They used to be independently settable
     * and reconciled by truthiness, which meant a stale `environment.path`
     * surviving an unrelated edit could silently overwrite a correct
     * `prefix` — not just duplicate data, an active corruption path. Making
     * the derivation one-way removes that failure mode structurally rather
     * than patching the specific case it was caught in.
     */
    function normalizeRecord(input) {
        var rec = Object.assign({}, root.template(), input || {});
        rec.window = Object.assign({}, root.template().window, input && input.window ? input.window : {});
        rec.performance = Object.assign({}, root.template().performance, input && input.performance ? input.performance : {});
        rec.env = Object.assign({}, input && input.env ? input.env : {});
        rec.dllOverrides = Object.assign({}, input && input.dllOverrides ? input.dllOverrides : {});
        rec.args = Array.isArray(input && input.args) ? input.args.slice() : [];
        rec.candidateExecutables = Array.isArray(input && input.candidateExecutables)
            ? input.candidateExecutables.map(item => Object.assign({}, item)) : [];
        rec.desktopEntryId = String(input && input.desktopEntryId ? input.desktopEntryId : "");

        var envInput = input && input.environment ? input.environment : {};
        rec.environment = {
            type: "wineprefix",
            path: rec.prefix || "",
            name: envInput.name || rec.name || "",
            arch: envInput.arch || "win64"
        };

        var rtInput = input && input.runtime ? input.runtime : {};
        rec.runtime = {
            provider: rec.runner || "native",
            variant: rtInput.variant || "",
            version: rtInput.version || "",
            build: rec.runner === "umu" ? (rec.protonBuild || "GE-Proton") : ""
        };

        return rec;
    }

    function runtimeFor(app) { return root.normalizeRecord(app).runtime; }
    function environmentFor(app) { return root.normalizeRecord(app).environment; }

    function byId(id) {
        for (var i = 0; i < root.apps.length; i++)
            if (root.apps[i].id === id)
                return root.apps[i];
        return null;
    }

    readonly property var byCategoryCache: {
        void root.apps;
        var out = {};
        for (var c = 0; c < root.categories.length; c++)
            out[root.categories[c].id] = [];
        for (var i = 0; i < root.apps.length; i++) {
            var a = root.apps[i];
            if (!out[a.category])
                out[a.category] = [];
            out[a.category].push(a);
        }
        for (var k in out) {
            out[k].sort((x, y) => {
                if (x.favorite !== y.favorite)
                    return x.favorite ? -1 : 1;
                return x.name.localeCompare(y.name);
            });
        }
        return out;
    }

    function appsFor(category) {
        return root.byCategoryCache[category] || [];
    }

    function countFor(category) {
        return root.appsFor(category).length;
    }

    function slugify(name) {
        var s = String(name).toLowerCase().trim().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "");
        return s.length > 0 ? s : "app";
    }

    function uniqueId(base) {
        var id = base, n = 2;
        while (root.byId(id) !== null) {
            id = base + "-" + n;
            n++;
        }
        return id;
    }

    /** Merges `partial` over template(), assigns a fresh unique id, appends and persists. Returns the stored record. */
    function add(partial) {
        if (!root.ready || root.loadError) {
            console.warn("AppRegistry: refusing to add an app while the registry is unavailable.");
            return null;
        }
        var rec = root.normalizeRecord(partial || {});
        rec.id = root.uniqueId(root.slugify(rec.name || rec.executable || "app"));
        rec.createdAt = Date.now();
        // New entries append to the established blade order. Runtime activity
        // never changes their order; layout code only changes angles/spacing.
        var maxBladeOrder = 0;
        for (var i = 0; i < root.apps.length; ++i)
            maxBladeOrder = Math.max(maxBladeOrder, Number(root.apps[i].bladeOrder) || 0);
        rec.bladeOrder = maxBladeOrder + 1;
        root.apps = root.apps.concat([rec]);
        root.persist();
        return rec;
    }

    function pathWithin(child, parent) {
        var c = String(child || "").replace(/\\/+$/, "");
        var p = String(parent || "").replace(/\\/+$/, "");
        return c.length > 0 && p.length > 0 && (c === p || c.indexOf(p + "/") === 0);
    }

    function sameJson(a, b) {
        try { return JSON.stringify(a) === JSON.stringify(b); }
        catch (e) { return false; }
    }

    /*
     * Reconcile the read-only folder index into the registry. Discovery only
     * creates/updates metadata; it never launches a candidate and never
     * deletes a user's record when a folder disappears.
     */
    function syncDiscovered(index) {
        if (!root.ready || root.loadError || !index || !Array.isArray(index.games))
            return;

        var next = root.apps.slice();
        var seen = ({});
        var changed = false;
        var games = index.games;
        var scanRoot = String(index.root || root.gamesDirectory);

        for (var g = 0; g < games.length; ++g) {
            var game = games[g];
            var source = String(game && game.sourcePath || "");
            if (!source)
                continue;
            seen[source] = true;

            var at = -1;
            for (var i = 0; i < next.length; ++i) {
                if (String(next[i].sourcePath || "") === source) {
                    at = i;
                    break;
                }
            }

            // Link an existing manually-created entry to its folder if the
            // selected executable is already inside it. Do not create a duplicate.
            if (at < 0) {
                for (var j = 0; j < next.length; ++j) {
                    var existing = next[j];
                    if (!existing.sourcePath && existing.executable
                            && pathWithin(existing.executable, String(game.gameFolder || source))) {
                        at = j;
                        break;
                    }
                }
            }

            if (at >= 0) {
                var old = next[at];
                var replacement = Object.assign({}, old, {
                    sourcePath: source,
                    gameFolder: String(game.gameFolder || source),
                    candidateExecutables: Array.isArray(game.candidateExecutables) ? game.candidateExecutables : [],
                    discovered: true,
                    folderMissing: false
                });
                if ((!old.executable || old.needsSetup) && game.executable) {
                    replacement.executable = String(game.executable);
                    replacement.workingDirectory = String(game.workingDirectory || game.gameFolder || source);
                    replacement.needsSetup = false;
                    if (/\\.exe$/i.test(replacement.executable) && !replacement.prefix)
                        replacement.prefix = root.dataHome + "/ricelin/prefixes/" + String(old.id);
                }
                replacement = root.normalizeRecord(replacement);
                if (!root.sameJson(old, replacement)) {
                    next[at] = replacement;
                    changed = true;
                }
                continue;
            }

            var name = String(game.name || source.split("/").pop() || "Game");
            var id = root.uniqueId(root.slugify(name));
            var executable = String(game.executable || "");
            var candidates = Array.isArray(game.candidateExecutables) ? game.candidateExecutables : [];
            var hasWindowsCandidate = /\\.exe$/i.test(executable)
                || candidates.some(item => String(item && item.kind || "") === "windows");
            var order = 0;
            for (var k = 0; k < next.length; ++k)
                order = Math.max(order, Number(next[k].bladeOrder) || 0);

            var record = root.normalizeRecord({
                id: id,
                name: name,
                category: "game",
                favorite: false,
                blade: "auto",
                bladeOrder: order + 1,
                runner: "auto",
                executable: executable,
                workingDirectory: String(game.workingDirectory || game.gameFolder || source),
                prefix: hasWindowsCandidate ? (root.dataHome + "/ricelin/prefixes/" + id) : "",
                sourcePath: source,
                gameFolder: String(game.gameFolder || source),
                candidateExecutables: candidates,
                needsSetup: !!game.needsSetup || !executable,
                discovered: true,
                folderMissing: false,
                createdAt: Date.now()
            });
            next.push(record);
            changed = true;
        }

        for (var m = 0; m < next.length; ++m) {
            var saved = next[m];
            if (!saved.discovered || !saved.sourcePath || !root.pathWithin(saved.sourcePath, scanRoot))
                continue;
            var isMissing = !seen[String(saved.sourcePath)];
            if (!!saved.folderMissing !== isMissing) {
                next[m] = root.normalizeRecord(Object.assign({}, saved, { folderMissing: isMissing }));
                changed = true;
            }
        }

        if (changed) {
            root.apps = next;
            root.persist();
        }
    }

    function scanGames() {
        if (!root.ready || root.loadError || gamesScanProc.running)
            return;
        gamesScanProc.running = true;
    }

    Process {
        id: gamesScanProc
        command: ["python3", root.gamesScanner, "--root", root.gamesDirectory]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.syncDiscovered(JSON.parse(this.text));
                } catch (e) {
                    console.warn("AppRegistry: the Games scanner returned invalid data:", String(e));
                }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                var message = String(this.text || "").trim();
                if (message.length > 0)
                    console.warn("AppRegistry Games scanner:", message);
            }
        }
        onExited: function(exitCode) {
            if (exitCode !== 0)
                console.warn("AppRegistry: Games scan exited with status", exitCode);
        }
    }

    Timer {
        interval: 30000
        repeat: true
        running: root.ready && !root.loadError
        onTriggered: root.scanGames()
    }

    function update(id, patch) {
        if (!root.ready || root.loadError) return;
        root.apps = root.apps.map(a => a.id === id ? root.normalizeRecord(Object.assign({}, a, patch || {})) : a);
        root.persist();
    }

    function remove(id) {
        if (!root.ready || root.loadError) return;
        root.apps = root.apps.filter(a => a.id !== id);
        root.persist();
    }

    function toggleFavorite(id) {
        var a = root.byId(id);
        if (a)
            root.update(id, { favorite: !a.favorite });
    }

    function recordLaunch(id) {
        var a = root.byId(id);
        if (a)
            root.update(id, { lastLaunched: Date.now(), launchCount: (a.launchCount || 0) + 1 });
    }

    /** First run: start with an empty list. Nothing machine-specific is baked in; the Add and Scan sheets are how apps arrive. */
    function seedDefaults() {
        root.apps = [];
        root.persist();
    }

    function persist() {
        if (!root.ready
                || (root.loadError && !root.recoveryWritePending)
                || (root.recovering && !root.recoveryWritePending))
            return;
        store.setText(JSON.stringify(root.apps, null, 2));
    }

    /** Receives the raw text of an unparsable store; written from memory, so nothing races the replacement file. */

    FileView {
        id: store
        path: root.path
        // Do not open applications.json until storeProbe has verified that it is
        // a regular, non-symlink file. This also avoids opening a FIFO on startup.
        preload: false
        blockLoading: true
        atomicWrites: true
        printErrors: false
        onSaved: {
            if (root.recoveryWritePending) {
                root.recoveryWritePending = false;
                root.recovering = false;
                root.loadError = "";
                root.ready = true;
                root.recoveryStatus = "Original registry backed up to " + root.recoveryBackupPath
                    + ". Defaults were written; the original file contents remain in that backup.";
                root.scanGames();
            } else if (root.recoveryStatus.indexOf("Could not save applications.json:") === 0) {
                root.recoveryStatus = "";
            }
        }
        onSaveFailed: function(error) {
            if (!root.recoveryWritePending) {
                root.recoveryStatus = "Could not save applications.json: " + String(error);
                console.warn("AppRegistry: could not save applications.json:", error);
                return;
            }
            root.recoveryWritePending = false;
            root.recovering = false;
            root.apps = [];
            root.loadError = "The registry backup exists, but writing defaults failed: " + String(error);
            root.recoveryStatus = "Original registry is backed up at " + root.recoveryBackupPath
                + ", but writing defaults failed. The backup retains the original file contents.";
            console.warn("AppRegistry: defaults could not be written after recovery backup:", error);
        }
    }

    /**
     * `~/.config/ricelin` may not exist yet on a fresh install, and setText()
     * needs it to already be there — so the very first load waits for this
     * mkdir to actually exit before touching the store, rather than firing
     * both in the same tick and racing it.
     */
    Process {
        id: mkdirProc
        command: ["mkdir", "-p", root.dir]
        onExited: function(exitCode) { // qmllint disable signal-handler-parameters
            if (exitCode !== 0) {
                root.finishLoadError("Could not create the registry directory: " + root.dir);
                return;
            }
            storeProbe.running = true;
        }
    }

    // Exit 0 means a regular file exists, exit 1 means it is definitely absent
    // and the parent is accessible, and exit 2 means unsafe/unknown. Only exit 1
    // may seed defaults; directories, special files and symlinks are never read.
    Process {
        id: storeProbe
        command: ["sh", "-c",
            "if [ -L \"$1\" ]; then exit 2; fi; "
            + "if [ -f \"$1\" ]; then exit 0; fi; "
            + "if [ -e \"$1\" ]; then exit 2; fi; "
            + "if [ -d \"$2\" ] && [ -r \"$2\" ] && [ -w \"$2\" ] && [ -x \"$2\" ]; then exit 1; fi; "
            + "exit 2", "_", root.path, root.dir]
        onExited: function(exitCode) { // qmllint disable signal-handler-parameters
            root.loadOrSeed(exitCode);
        }
    }

    Process {
        id: backupProc
        command: ["true"]
        running: false
        onExited: function(exitCode) { // qmllint disable signal-handler-parameters
            if (exitCode !== 0) {
                root.recovering = false;
                root.recoveryBackupPath = "";
                root.recoveryStatus = "Backup failed; the original registry was not changed.";
                console.warn("AppRegistry: backup failed; refusing default recovery.");
                return;
            }
            // Keep the registry locked until FileView confirms the defaults were saved.
            root.ready = true;
            root.recoveryWritePending = true;
            root.seedDefaults();
        }
    }

    function finishLoadError(reason) {
        root.apps = [];
        root.loadError = String(reason);
        root.ready = true; // loading has finished, but mutations/persistence remain disabled
        root.recoveryStatus = "";
        root.recoveryWritePending = false;
        console.warn("AppRegistry: " + root.loadError + ". Existing applications.json was not overwritten.");
    }

    function loadOrSeed(pathState) {
        if (pathState === 1) {
            root.loadError = "";
            root.ready = true;
            root.seedDefaults();
            root.scanGames();
            return;
        }
        if (pathState !== 0) {
            root.finishLoadError("applications.json is not a regular non-symlink file, or its path state could not safely be determined.");
            return;
        }

        var raw = "";
        try {
            raw = store.text();
        } catch (e) {
            root.finishLoadError("Could not read applications.json: " + String(e));
            return;
        }
        if (!store.loaded) {
            root.finishLoadError("The existing applications.json could not be loaded; its contents were preserved.");
            return;
        }

        var records;
        try {
            records = RegistryStore.parse(raw);
        } catch (e) {
            root.finishLoadError("applications.json is invalid: " + String(e));
            return;
        }

        root.apps = records.map(a => root.normalizeRecord(a));
        root.loadError = "";
        root.ready = true;
        root.scanGames();
    }

    // This recovery path is deliberately explicit: it backs up the exact old
    // file first and writes defaults only after that copy has succeeded.
    function recoverWithDefaults() {
        if (!root.loadError || root.recovering
                || root.recoveryWritePending || !root.ready)
            return false;
        var backup = root.path + ".backup-" + Date.now();
        root.recoveryBackupPath = backup;
        root.recoveryStatus = "Backing up the existing registry before writing defaults…";
        backupProc.command = ["sh", "-c",
            "set -eu; if [ -L \"$1\" ]; then exit 5; fi; "
            + "if [ -f \"$1\" ]; then "
            + "[ ! -e \"$2\" ] && [ ! -L \"$2\" ] || exit 3; cp -p -- \"$1\" \"$2\"; "
            + "else exit 4; fi", "_", root.path, backup];
        root.recovering = true;
        backupProc.running = true;
        return true;
    }

    Component.onCompleted: mkdirProc.running = true
}
