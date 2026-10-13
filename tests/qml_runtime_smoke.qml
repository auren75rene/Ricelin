import QtQuick
import Quickshell
import "Singletons"

ShellRoot {
    Component.onCompleted: {
        var methods = [
            EnvironmentManager.create,
            EnvironmentManager.openFiles,
            EnvironmentManager.winetricks,
            EnvironmentManager.clone,
            EnvironmentManager.reset,
            EnvironmentManager.remove
        ];
        for (var i = 0; i < methods.length; ++i) {
            if (typeof methods[i] !== "function") {
                console.error("RICELIN_QML_RUNTIME_SMOKE_FAIL: EnvironmentManager API is incomplete");
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
