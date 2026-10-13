import QtQuick
import Quickshell
import "../configs/quickshell/pill/Singletons"

ShellRoot {
    Component.onCompleted: {
        var methods = ["create", "openFiles", "winetricks", "clone", "reset", "remove"];
        for (var i = 0; i < methods.length; ++i) {
            if (typeof EnvironmentManager[methods[i]] !== "function") {
                console.error("RICELIN_QML_RUNTIME_SMOKE_FAIL: missing EnvironmentManager." + methods[i]);
                Qt.quit();
                return;
            }
        }

        var prefix = Quickshell.env("RICELIN_TEST_PREFIX") || "";
        var executable = Quickshell.env("RICELIN_TEST_EXECUTABLE") || "";
        var workingDirectory = Quickshell.env("RICELIN_TEST_WORKDIR") || "";
        if (!prefix || !executable || !workingDirectory) {
            console.error("RICELIN_QML_RUNTIME_SMOKE_FAIL: test paths were not provided");
            Qt.quit();
            return;
        }

        if (!EnvironmentManager.create({
            prefix: prefix,
            runner: "umu",
            executable: executable,
            workingDirectory: workingDirectory
        })) {
            console.error("RICELIN_QML_RUNTIME_SMOKE_FAIL: create action was not dispatched");
            Qt.quit();
            return;
        }

        console.log("RICELIN_QML_RUNTIME_SMOKE_DISPATCHED");
        Qt.quit();
    }
}
