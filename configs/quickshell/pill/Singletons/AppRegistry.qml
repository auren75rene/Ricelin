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
    // Do not scan/write discovered games until first-run defaults or legacy
    // registry migration has completed its atomic save.
    property bool scanAfterSeed: false

    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || ((Quickshell.env("HOME") || "") + "/.config")
    readonly property string dataHome: Quickshell.env("XDG_DATA_HOME") || ((Quickshell.env("HOME") || "") + "/.local/share")
    readonly property string dir: root.configHome + "/ricelin"
    readonly property string path: root.dir + "/applications.json"
    readonly property string gamesDirectory: Quickshell.env("RICELIN_GAMES_DIR") || ((Quickshell.env("HOME") || "") + "/Games")
    readonly property string gameDiscovery: root.configHome + "/hypr/scripts/ricelin-game-discovery"

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

    readonly property var recentApps: {
        void root.apps;
        return root.apps.filter(a => Number(a.lastLaunched || 0) > 0 || Number(a.launchCount || 0) > 0)
            .slice().sort((a, b) => {
                var byTime = Number(b.lastLaunched || 0) - Number(a.lastLaunched || 0);
                if (byTime !== 0) return byTime;
                return Number(b.launchCount || 0) - Number(a.launchCount || 0);
            });
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

    function withoutTrailingSlashes(value) {
        var path = String(value || "");
        while (path.length > 1 && path.charAt(path.length - 1) === "/")
            path = path.slice(0, -1);
        return path;
    }

    function pathWithin(child, parent) {
        var c = root.withoutTrailingSlashes(child);
        var p = root.withoutTrailingSlashes(parent);
        return c.length > 0 && p.length > 0 && (c === p || c.indexOf(p + "/") === 0);
    }

    function sameJson(a, b) {
        try { return JSON.stringify(a) === JSON.stringify(b); }
        catch (e) { return false; }
    }

    /*
     * Reconcile the shared source-aware inventory with records already
     * registered. A background scan may refresh metadata, but it never imports
     * a new candidate or overwrites the user's launch settings.
     */
    function syncDiscovered(index) {
        if (!root.ready || root.loadError || !index || !Array.isArray(index.games))
            return;

        var next = root.apps.slice();
        var changed = false;
        var seenLocal = ({});
        var scanRoot = root.withoutTrailingSlashes(root.gamesDirectory);

        function pathKey(value) {
            return root.withoutTrailingSlashes(String(value || ""));
        }
        function matches(existing, candidate) {
            var appid = String(candidate.steamAppId || "");
            if (appid && String(existing.steamAppId || existing.steamAppid || "") === appid)
                return true;
            var desktopId = String(candidate.desktopEntryId || "");
            if (desktopId && String(existing.desktopEntryId || "").toLowerCase() === desktopId.toLowerCase())
                return true;
            var executable = pathKey(candidate.executable);
            if (executable && pathKey(existing.executable) === executable)
                return true;
            var source = pathKey(candidate.sourceId);
            var install = pathKey(candidate.installDirectory);
            if (source && pathKey(existing.sourcePath) === source)
                return true;
            if (candidate.source === "local-directory" && existing.executable && install
                    && root.pathWithin(existing.executable, install))
                return true;
            return false;
        }

        for (var g = 0; g < index.games.length; ++g) {
            var candidate = index.games[g] || {};
            var local = candidate.source === "local-directory";
            var source = String(candidate.sourceId || candidate.installDirectory || "");
            if (local && source) {
                seenLocal[pathKey(source)] = true;
                if (candidate.installDirectory)
                    seenLocal[pathKey(candidate.installDirectory)] = true;
            }

            var at = -1;
            for (var i = 0; i < next.length; ++i) {
                if (matches(next[i], candidate)) {
                    at = i;
                    break;
                }
            }
            // Deliberately no "add" path here: users import from the Scan UI.
            if (at < 0)
                continue;

            var old = next[at];
            var patch = {};
            if (local) {
                if (!old.sourcePath && source)
                    patch.sourcePath = source;
                if (!old.gameFolder && candidate.installDirectory)
                    patch.gameFolder = String(candidate.installDirectory);
                if ((!Array.isArray(old.candidateExecutables) || old.candidateExecutables.length === 0)
                        && candidate.executable) {
                    patch.candidateExecutables = [{
                        path: String(candidate.executable),
                        name: String(candidate.name || ""),
                        kind: String(candidate.executable).toLowerCase().endsWith(".exe") ? "windows" : "native",
                        score: 0
                    }];
                }
                patch.discovered = true;
                patch.folderMissing = false;
            }
            if (!old.desktopEntryId && candidate.desktopEntryId)
                patch.desktopEntryId = String(candidate.desktopEntryId);
            if (!old.steamAppId && candidate.steamAppId)
                patch.steamAppId = String(candidate.steamAppId);
            if (!old.workingDirectory && candidate.workingDirectory)
                patch.workingDirectory = String(candidate.workingDirectory);
            if (!old.prefix && candidate.prefix)
                patch.prefix = String(candidate.prefix);

            var replacement = root.normalizeRecord(Object.assign({}, old, patch));
            if (!root.sameJson(old, replacement)) {
                next[at] = replacement;
                changed = true;
            }
        }

        // Missing-folder state applies only to previously discovered local
        // paths under the configured Games root, not Steam/Lutris/desktop data.
        for (var m = 0; m < next.length; ++m) {
            var saved = next[m];
            if (!saved.discovered || !saved.sourcePath || !root.pathWithin(saved.sourcePath, scanRoot))
                continue;
            var isMissing = !seenLocal[pathKey(saved.sourcePath)];
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
        command: ["python3", root.gameDiscovery, "--home", Quickshell.env("HOME") || "", "--root", root.gamesDirectory]
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
                    console.warn("AppRegistry game discovery:", message);
            }
        }
        onExited: function(exitCode) {
            if (exitCode !== 0)
                console.warn("AppRegistry: Games scan exited with status", exitCode);
        }
    }

    Timer {
        // The scanner walks a bounded depth into each game folder. Avoid
        // repeatedly traversing large game payloads; new games usually appear
        // within a minute, and a manual scan can be added to the UI later.
        interval: 60000
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
            } else if (root.scanAfterSeed) {
                root.scanAfterSeed = false;
                root.scanGames();
            } else if (root.recoveryStatus.indexOf("Could not save applications.json:") === 0) {
                root.recoveryStatus = "";
            }
        }
        onSaveFailed: function(error) {
            if (!root.recoveryWritePending) {
                root.scanAfterSeed = false;
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
            root.scanAfterSeed = true;
            root.seedDefaults();
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

        var needsOrderMigration = false;
        var maxSavedOrder = 0;
        for (var oi = 0; oi < records.length; ++oi) {
            var savedOrder = Number(records[oi] && records[oi].bladeOrder);
            if (isFinite(savedOrder) && savedOrder > maxSavedOrder)
                maxSavedOrder = savedOrder;
        }
        root.apps = records.map((a) => {
            var rec = root.normalizeRecord(a);
            if (!isFinite(Number(a && a.bladeOrder)) || Number(a && a.bladeOrder) <= 0) {
                // Legacy entries keep their serialized order and are appended
                // after any entries that already have an explicit stable order.
                maxSavedOrder += 10;
                rec.bladeOrder = maxSavedOrder;
                needsOrderMigration = true;
            }
            return rec;
        });
        root.loadError = "";
        root.ready = true;
        if (needsOrderMigration) {
            root.scanAfterSeed = true;
            root.persist();
        } else {
            root.scanGames();
        }
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
