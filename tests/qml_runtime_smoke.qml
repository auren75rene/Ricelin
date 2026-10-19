import QtQuick
import Quickshell
import Quickshell.Io
import "Singletons"
import "lib/desktopentry.js" as DesktopImport
import "Pill" as Pill

ShellRoot {
    id: root

    property int attempts: 0
    property string testAppId: ""
    property bool launchDispatched: false
    property bool prefixEnsureDone: false
    property string prefixEnsureError: ""
    property bool gameScanChecked: false

    Component {
        id: addStyleFormComponent
        Pill.AddStyleSheet {
            width: 520
            s: 1
            visible: false
        }
    }

    function fail(reason) {
        console.error("RICELIN_QML_RUNTIME_SMOKE_FAIL: " + reason)
        stageTimer.stop()
    }

    function pass() {
        console.log("RICELIN_QML_RUNTIME_SMOKE_PASS")
        stageTimer.stop()
    }

    Component.onCompleted: {
        // Compile and instantiate the actual style-registration form in CI.
        // It stays hidden and submits nothing, so no user's dotfiles are touched.
        var styleForm = addStyleFormComponent.createObject(null, { width: 520, s: 1, visible: false });
        if (!styleForm) {
            fail("AddStyleSheet could not be instantiated");
            return;
        }
        if (styleForm.canAdd) {
            styleForm.destroy();
            fail("an empty AddStyleSheet form should not be submittable");
            return;
        }
        styleForm.destroy();

        var methods = [
            EnvironmentManager.create,
            EnvironmentManager.openFiles,
            EnvironmentManager.winetricks,
            EnvironmentManager.clone,
            EnvironmentManager.reset,
            EnvironmentManager.remove,
            EnvironmentManager.ensurePrefix
        ]
        for (var i = 0; i < methods.length; ++i) {
            if (typeof methods[i] !== "function") {
                fail("EnvironmentManager API is incomplete")
                return
            }
        }

        var prefix = Quickshell.env("RICELIN_TEST_PREFIX") || ""
        var executable = Quickshell.env("RICELIN_TEST_EXECUTABLE") || ""
        var workingDirectory = Quickshell.env("RICELIN_TEST_WORKDIR") || ""
        if (!prefix || !executable || !workingDirectory) {
            fail("prefix test paths were not provided")
            return
        }

        if (!EnvironmentManager.ensurePrefix({
            prefix: prefix,
            runner: "umu",
            executable: executable,
            workingDirectory: workingDirectory
        }, function(ok, message) {
            root.prefixEnsureDone = true;
            if (!ok)
                root.prefixEnsureError = String(message || "unknown prefix preparation error");
        })) {
            fail("prefix ensure action was not dispatched")
            return
        }

        var v4l2Path = CameraRec.v4l2DevicePath()
        if (v4l2Path && !/^\/dev\/video[0-9]+$/.test(v4l2Path)) {
            fail("camera resolver returned an invalid V4L2 path")
            return
        }
        // Validate the public CaptureSession reference without activating a
        // physical camera. Recorder.qml uses this object to attach VideoOutput.
        var captureSession = CameraRec.captureSession
        if (!captureSession || !captureSession.camera ||
            !captureSession.imageCapture || !captureSession.recorder) {
            fail("CameraRec did not expose its CaptureSession and media objects")
            return
        }

        // Load the screen-recorder singleton itself, but never start recording.
        // This exercises the changed QML import/property path in a headless run.
        if (typeof ScreenRec.start !== "function" ||
            typeof ScreenRec.stop !== "function") {
            fail("ScreenRec start/stop API is unavailable")
            return
        }
        if (ScreenRec.recording || ScreenRec.canStop || ScreenRec.busy) {
            fail("screen recorder should be idle at smoke-test startup")
            return
        }
        ScreenRec.start("")
        if (ScreenRec.busy) {
            fail("screen recorder accepted an empty capture target")
            return
        }
    }

    Timer {
        id: stageTimer
        interval: 100
        repeat: true
        running: true

        onTriggered: {
            root.attempts += 1
            if (root.attempts > 150) {
                var diagnostics = "AppRegistry.ready=" + AppRegistry.ready
                    + ", loadError=" + AppRegistry.loadError
                    + ", desktopEntries=" + (DesktopEntries.applications.values || []).length
                var values = DesktopEntries.applications.values || []
                var matches = []
                for (var j = 0; j < values.length; ++j) {
                    var candidate = values[j]
                    if (candidate && (String(candidate.id || "").toLowerCase().indexOf("ricelin") >= 0
                        || String(candidate.name || "").toLowerCase().indexOf("ricelin") >= 0)) {
                        matches.push(String(candidate.id || "") + " (" + String(candidate.name || "") + ")")
                    }
                }
                root.fail("timeout state: " + diagnostics + "; matching entries=" + JSON.stringify(matches))
                return
            }

            if (root.prefixEnsureError.length > 0) {
                root.fail("prefix ensure failed: " + root.prefixEnsureError)
                return
            }
            if (!root.prefixEnsureDone)
                return

            if (!AppRegistry.ready)
                return
            if (AppRegistry.loadError.length > 0) {
                root.fail("application registry did not load: " + AppRegistry.loadError)
                return
            }

            var expectedGameFolder = Quickshell.env("RICELIN_TEST_GAME_FOLDER") || ""
            var expectedGameExecutable = Quickshell.env("RICELIN_TEST_EXECUTABLE") || ""
            if (expectedGameFolder.length > 0 && !root.gameScanChecked) {
                var discoveredGame = null
                for (var g = 0; g < AppRegistry.apps.length; ++g) {
                    var gameRecord = AppRegistry.apps[g]
                    if (gameRecord && gameRecord.discovered
                            && String(gameRecord.sourcePath || "") === expectedGameFolder) {
                        discoveredGame = gameRecord
                        break
                    }
                }
                // The scanner is an asynchronous Process; let its first poll finish.
                if (!discoveredGame)
                    return
                if (String(discoveredGame.executable || "") !== expectedGameExecutable || discoveredGame.needsSetup) {
                    root.fail("Games scanner did not register the expected executable: " + JSON.stringify(discoveredGame))
                    return
                }
                if (String(discoveredGame.prefix || "").indexOf("/ricelin/prefixes/") < 0) {
                    root.fail("discovered Windows game did not receive a dedicated prefix outside its game folder")
                    return
                }
                root.gameScanChecked = true
            }

            var desktopExecutable = Quickshell.env("RICELIN_TEST_DESKTOP_EXECUTABLE") || ""
            var argvLog = Quickshell.env("RICELIN_TEST_ARGV_LOG") || ""
            var expectedWorkdir = Quickshell.env("RICELIN_TEST_WORKDIR") || ""
            if (!desktopExecutable || !argvLog || !expectedWorkdir) {
                root.fail("desktop-entry test paths were not provided")
                return
            }

            var values = DesktopEntries.applications.values || []
            var entry = null
            for (var i = 0; i < values.length; ++i) {
                if (values[i] && (String(values[i].id || "") === "org.ricelin.runtime-smoke" || String(values[i].id || "") === "org.ricelin.runtime-smoke.desktop") && !values[i].noDisplay) {
                    entry = values[i]
                    break
                }
            }
            if (!entry)
                return

            var imported = DesktopImport.fromEntry(entry, "utility")
            if (imported.executable !== desktopExecutable) {
                root.fail("desktop entry executable was not parsed as one argv item")
                return
            }
            if (imported.args.length !== 3 ||
                imported.args[0] !== "--alpha" ||
                imported.args[1] !== "value with spaces" ||
                imported.args[2] !== "--beta") {
                root.fail("desktop entry arguments were not parsed losslessly: " + JSON.stringify(imported.args))
                return
            }

            // Empty workingDirectory deliberately exercises fallback to the .desktop
            // entry's Path= instead of a registry override.
            imported.workingDirectory = ""
            imported.env = Object.assign({}, imported.env || {}, { RICELIN_TEST_ARGV_LOG: argvLog })

            var preview = AppLauncher.buildInvocation(imported)
            if (preview.command.length !== 4 ||
                preview.command[0] !== desktopExecutable ||
                preview.command[1] !== "--alpha" ||
                preview.command[2] !== "value with spaces" ||
                preview.command[3] !== "--beta") {
                root.fail("AppLauncher preview changed imported argv: " + JSON.stringify(preview.command))
                return
            }
            if (preview.workingDirectory !== expectedWorkdir) {
                root.fail("AppLauncher did not use the desktop entry working directory: " + preview.workingDirectory)
                return
            }

            var stored = AppRegistry.add(imported)
            if (!stored) {
                root.fail("could not register the temporary imported desktop entry")
                return
            }
            root.testAppId = stored.id
            AppLauncher.launch(stored.id, false)
            if (!AppLauncher.isRunning(stored.id)) {
                root.fail("AppLauncher did not start the imported desktop entry")
                return
            }
            root.launchDispatched = true
            stageTimer.stop()
            launchPoll.start()
        }
    }

    Timer {
        id: launchPoll
        interval: 50
        repeat: true
        onTriggered: {
            if (root.testAppId && !AppLauncher.isRunning(root.testAppId)) {
                stop()
                verifyLaunch.command = ["cat", Quickshell.env("RICELIN_TEST_ARGV_LOG") || ""]
                verifyLaunch.running = true
            }
        }
    }

    Process {
        id: verifyLaunch
        stdout: StdioCollector {
            id: launchOutput
        }

        onExited: function(exitCode) {
            if (exitCode !== 0) {
                root.fail("launched test executable did not produce its argv log")
                return
            }

            var actual = String(launchOutput.text || "").replace(/\n+$/, "").split("\n")
            var expected = [
                "arg=--alpha",
                "arg=value with spaces",
                "arg=--beta",
                "cwd=" + (Quickshell.env("RICELIN_TEST_WORKDIR") || "")
            ]
            if (actual.length !== expected.length) {
                root.fail("wrong number of argv/cwd lines: " + JSON.stringify(actual))
                return
            }
            for (var i = 0; i < expected.length; ++i) {
                if (actual[i] !== expected[i]) {
                    root.fail("imported app launch mismatch at line " + i + ": " + actual[i])
                    return
                }
            }
            root.pass()
        }
    }
}
