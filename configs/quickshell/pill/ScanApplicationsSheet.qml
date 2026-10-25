pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "Singletons"

/**
 * "Add → Scan": discover applications from ~/Games, Steam, Lutris and
 * desktop entries.
 *
 * Steam infrastructure (Proton, SteamLinuxRuntime, Steamworks Shared, etc.)
 * is intentionally excluded: those are runtime/tool components rather than
 * user applications.
 *
 * Steam candidates are deduplicated by App ID because the same Steam library
 * can be reachable through several conventional Steam paths.
 */
Item {
    id: root

    property real s: 1
    signal back()
    signal imported(int count)

    implicitHeight: col.implicitHeight

    property bool scanning: true
    property string scanError: ""
    property var candidates: []
    property var checked: ({})

    readonly property var existingExecs: AppRegistry.apps.map(a => a.executable)
    readonly property int selectedCount:
        Object.keys(root.checked).filter(k => root.checked[k] === true).length

    function rescan() {
        root.scanning = true
        root.candidates = []
        root.checked = ({})
        root.scanError = ""
        scanProc.running = true
    }

    function toggle(idx) {
        var next = Object.assign({}, root.checked)
        next[idx] = !root.checked[idx]
        root.checked = next
    }

    function selectAll() {
        var next = ({})
        for (var i = 0; i < root.candidates.length; i++) {
            if (root.candidates[i].source !== "STEAM" ||
                root.candidates[i].steamAppId) {
                next[i] = true
            }
        }
        root.checked = next
    }

    function clearSelection() {
        root.checked = ({})
    }

    function isSteamInfrastructure(name) {
        var n = (name || "").trim().toLowerCase()

        return n === "proton" ||
               n.indexOf("proton ") === 0 ||
               n.indexOf("steamlinuxruntime") === 0 ||
               n.indexOf("steam linux runtime") === 0 ||
               n === "steamworks shared" ||
               n === "steamworks common redistributables" ||
               n === "steam controller configs"
    }

   function candidateKey(c) {
       if (c.id && String(c.id).length > 0)
           return String(c.id)

       if (c.steamAppId && String(c.steamAppId).length > 0)
           return "steam:" + String(c.steamAppId)

       if (c.desktopEntryId && String(c.desktopEntryId).length > 0)
           return "desktop:" + String(c.desktopEntryId).toLowerCase()

       if (c.executable && String(c.executable).length > 0)
           return "exec:" + String(c.executable).trim().toLowerCase()

       return "name:" + (c.name || "").trim().toLowerCase()
   }

   Component.onCompleted: root.rescan()

        Process {
        id: scanProc
        command: ["python3", AppRegistry.gameDiscovery,
                  "--home", Quickshell.env("HOME") || "",
                  "--root", AppRegistry.gamesDirectory]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var report = JSON.parse(this.text || "{}")
                    if (!report.games || !Array.isArray(report.games))
                        throw new Error("discovery output has no games array")
                    if (report.registry && report.registry.exists && !report.registry.readable)
                        throw new Error("applications.json could not be read safely")

                    var found = []
                    for (var i = 0; i < report.games.length; ++i) {
                        var item = report.games[i] || {}
                        if (item.alreadyRegistered)
                            continue
                        var appid = String(item.steamAppId || "")
                        var executable = appid ? "" : String(item.executable || "")
                        var source = String(item.source || "")
                        var uiSource = source === "steam" || source === "steam-desktop" ? "STEAM"
                            : source === "local-directory" ? "GAMESFOLDER"
                            : source === "lutris" ? "LUTRIS"
                            : source === "wine-desktop" ? "WINE_DESKTOP" : "DESKTOP"
                        var runner = appid ? "steam" : String(item.runner || "")
                        if (runner === "lutris" || !runner)
                            runner = executable.toLowerCase().endsWith(".exe") ? "wine" : "native"
                        if (runner === "native" && executable.toLowerCase().endsWith(".exe"))
                            runner = "wine"
                        var candidate = {
                            id: String(item.id || ""),
                            source: uiSource,
                            sourceKind: source,
                            name: String(item.name || ""),
                            category: "game",
                            executable: executable,
                            prefix: String(item.prefix || ""),
                            steamAppId: appid,
                            desktopEntryId: String(item.desktopEntryId || ""),
                            desktopEntry: String(item.desktopEntry || ""),
                            installPath: String(item.installDirectory || ""),
                            sourcePath: source === "local-directory" ? String(item.sourceId || "") : "",
                            gameFolder: source === "local-directory" ? String(item.installDirectory || "") : "",
                            workingDirectory: String(item.workingDirectory || ""),
                            runner: runner,
                            args: Array.isArray(item.args) ? item.args : [],
                            env: item.env || {},
                            startupWMClass: String(item.startupWMClass || ""),
                            needsSetup: !!item.needsSetup,
                            candidateExecutables: executable ? [{
                                path: executable,
                                name: String(item.name || ""),
                                kind: executable.toLowerCase().endsWith(".exe") ? "windows" : "native",
                                score: 0
                            }] : [],
                            evidence: Array.isArray(item.evidence) ? item.evidence : []
                        }
                        var represented = AppRegistry.apps.some(function(app) {
                            if (candidate.steamAppId &&
                                String(app.steamAppId || app.steamAppid || "") === candidate.steamAppId)
                                return true
                            if (candidate.desktopEntryId &&
                                String(app.desktopEntryId || "").toLowerCase() === candidate.desktopEntryId.toLowerCase())
                                return true
                            return !!candidate.executable &&
                                String(app.executable || "").toLowerCase() === candidate.executable.toLowerCase()
                        })
                        if (!represented)
                            found.push(candidate)
                    }

                    var seen = ({})
                    root.candidates = found.filter(function(candidate) {
                        if (!candidate.name)
                            return false
                        var key = root.candidateKey(candidate)
                        if (seen[key])
                            return false
                        seen[key] = true
                        return true
                    })
                    root.checked = ({})
                    root.scanning = false
                    root.scanError = ""
                } catch (e) {
                    root.candidates = []
                    root.checked = ({})
                    root.scanning = false
                    root.scanError = "Discovery failed: " + String(e)
                    console.warn("ScanApplicationsSheet: shared game discovery failed:", String(e))
                }
            }
        }

        stderr: StdioCollector {
            onStreamFinished: {
                var message = String(this.text || "").trim()
                if (message.length > 0)
                    console.warn("ScanApplicationsSheet discovery:", message)
            }
        }

        onExited: function(exitCode) {
            if (exitCode !== 0 && root.scanning) {
                root.scanning = false
                root.scanError = "Discovery exited with status " + exitCode
            }
        }
    }

    function sourceLabel(source) {
        return source === "GAMESFOLDER"
            ? "~/Games"
            : source === "STEAM"
                ? "Steam"
                : source === "LUTRIS"
                    ? "Lutris"
                    : source === "WINE_DESKTOP"
                        ? "Wine launcher"
                        : "Desktop"
    }

    component CandidateRow: Item {
        id: crow

        required property int index
        required property var modelData

        readonly property bool importable:
            crow.modelData.source !== "STEAM" ||
            !!crow.modelData.steamAppId

        readonly property bool on:
            crow.importable && root.checked[crow.index] === true

        width: parent ? parent.width : 0
        height: 48 * root.s

        opacity: crow.importable ? 1 : 0.56

        Rectangle {
            anchors.fill: parent
            anchors.topMargin: 2 * root.s
            anchors.bottomMargin: 2 * root.s
            radius: 10 * root.s

            color: crow.on
                ? Qt.alpha(Theme.onGlow, 0.10)
                : (rowHover.hovered ? Theme.frameBg : "transparent")

            Behavior on color {
                ColorAnimation { duration: Motion.fast }
            }
        }

        HoverHandler {
            id: rowHover
            enabled: crow.importable
        }

        MouseArea {
            anchors.fill: parent
            enabled: crow.importable
            cursorShape: Qt.PointingHandCursor
            onClicked: root.toggle(crow.index)
        }

        Rectangle {
            id: checkBox

            anchors.left: parent.left
            anchors.leftMargin: 10 * root.s
            anchors.verticalCenter: parent.verticalCenter

            width: 19 * root.s
            height: 19 * root.s
            radius: 6 * root.s

            color: crow.on
                ? Theme.vermDeep
                : (rowHover.hovered ? Qt.alpha(Theme.frameBg, 0.8)
                                     : "transparent")

            border.width: crow.on ? 0 : 1.4
            border.color: crow.on
                ? "transparent"
                : (rowHover.hovered ? Theme.iconDim : Theme.frameBorder)

            Behavior on color {
                ColorAnimation { duration: Motion.fast }
            }

            GlyphIcon {
                anchors.centerIn: parent
                visible: crow.on
                width: 11 * root.s
                height: 11 * root.s
                name: "check"
                color: Theme.bright
                stroke: 2.4
            }
        }

        Column {
            id: textCol

            anchors.left: checkBox.right
            anchors.leftMargin: 10 * root.s
            anchors.right: tag.left
            anchors.rightMargin: 10 * root.s
            anchors.verticalCenter: parent.verticalCenter

            spacing: 2 * root.s

            Text {
                width: parent.width
                text: crow.modelData.name
                color: Theme.cream
                font.family: Theme.font
                font.pixelSize: 12 * root.s
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }

            Text {
                width: parent.width

                text: crow.modelData.source === "STEAM"
                    ? (crow.importable
                        ? "Steam App ID " + crow.modelData.steamAppId
                        : "Steam · needs manual App ID")
                    : crow.modelData.source === "WINE_DESKTOP"
                        ? (String(crow.modelData.runner || "wine").toUpperCase() + " · " + String(crow.modelData.prefix || "prefix not detected"))
                        : crow.modelData.executable

                color: crow.importable ? Theme.faint : Theme.subtle
                font.family: Theme.font
                font.pixelSize: 9.5 * root.s
                elide: Text.ElideMiddle
            }
        }

       Rectangle {
           id: tag

           anchors.right: parent.right
           anchors.rightMargin: 10 * root.s
           anchors.verticalCenter: parent.verticalCenter

           width: tagText.implicitWidth + 28 * root.s
           height: 30 * root.s
           radius: 10 * root.s

           property real hoverScale: tagHover.hovered ? 1.08 : 1.0

           color: crow.importable
               ? Theme.tileBg
               : Qt.alpha(Theme.tileBg, 0.55)

           border.width: tagHover.hovered ? 2 : 1
           border.color: tagHover.hovered
               ? Theme.cream
               : Theme.hairSoft

           transform: Scale {
               origin.x: tag.width / 2
               origin.y: tag.height / 2
               xScale: tag.hoverScale
               yScale: tag.hoverScale
           }

           Behavior on hoverScale {
               SpringAnimation {
                   spring: 3.5
                   damping: 0.3
               }
           }

           Behavior on border.width {
               NumberAnimation {
                   duration: Motion.fast
               }
           }

           Row {
               anchors.centerIn: parent
               spacing: 7 * root.s

               Text {
                   text: crow.importable ? "◆" : "·"
                   color: crow.importable ? Theme.cream : Theme.subtle
                   font.family: Theme.font
                   font.pixelSize: 8 * root.s
                   font.weight: Font.Bold
               }

               Text {
                   id: tagText
                   text: crow.importable
                       ? root.sourceLabel(crow.modelData.source)
                       : "Manual"

                   color: crow.importable ? Theme.faint : Theme.subtle
                   font.family: Theme.font
                   font.pixelSize: 9 * root.s
                   font.weight: Font.Bold
               }
           }

           HoverHandler {
               id: tagHover
               cursorShape: Qt.PointingHandCursor
           }
       }
    }

    component TextButton: Rectangle {
        id: tb

        property string label: ""
        property bool primary: false
        signal clicked()

        implicitWidth: tbLabel.implicitWidth + 22 * root.s
        implicitHeight: 32 * root.s

        radius: 9 * root.s
        opacity: tb.enabled ? 1 : 0.5

        color: tb.primary
            ? Theme.vermDeep
            : (tbArea.containsMouse ? Theme.frameBg : "transparent")

        border.width: 1
        border.color: tb.primary ? "transparent" : Theme.frameBorder

        Text {
            id: tbLabel
            anchors.centerIn: parent
            text: tb.label
            color: tb.primary ? Theme.bright : Theme.cream
            font.family: Theme.font
            font.pixelSize: 11.5 * root.s
            font.weight: Font.Bold
        }

        MouseArea {
            id: tbArea
            anchors.fill: parent
            enabled: tb.enabled
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: tb.clicked()
        }
    }

    Column {
        id: col

        width: parent.width
        spacing: 0

        Item {
            width: parent.width
            height: 24 * root.s

            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8 * root.s

                GlyphIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 15 * root.s
                    height: 15 * root.s
                    name: "chevron-left"
                    color: backArea.containsMouse
                        ? Theme.cream
                        : Theme.iconDim
                    stroke: 2.2

                    MouseArea {
                        id: backArea
                        anchors.fill: parent
                        anchors.margins: -6 * root.s
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.back()
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Scan"
                    color: Theme.cream
                    font.family: Theme.font
                    font.pixelSize: 13 * root.s
                    font.weight: Font.Bold
                }
            }

            GlyphIcon {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 15 * root.s
                height: 15 * root.s
                name: "reboot"
                color: rescanArea.containsMouse
                    ? Theme.cream
                    : Theme.iconDim
                stroke: 1.8

                MouseArea {
                    id: rescanArea
                    anchors.fill: parent
                    anchors.margins: -6 * root.s
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.rescan()
                }
            }
        }

        Item {
            width: 1
            height: 10 * root.s
        }

        Row {
            visible: !root.scanning
            width: parent.width
            spacing: 8 * root.s

            Text {
                text: root.candidates.length === 1
                    ? "1 new application"
                    : root.candidates.length + " new applications"

                color: Theme.cream
                font.family: Theme.font
                font.pixelSize: 11 * root.s
                font.weight: Font.DemiBold
            }

            Text {
                visible: root.selectedCount > 0
                text: "· " + root.selectedCount + " selected"
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: 10.5 * root.s
            }
        }

        Text {
            visible: root.scanning
            text: "Scanning Steam, local games, Wine launchers and Lutris…"
            color: Theme.faint
            font.family: Theme.font
            font.pixelSize: 11 * root.s
        }

        Text {
            visible: !root.scanning && root.candidates.length === 0
            width: parent.width
            wrapMode: Text.WordWrap
            text: "No new applications found. Everything already in your library has been filtered out."
            color: Theme.faint
            font.family: Theme.font
            font.pixelSize: 11 * root.s
        }

        Item {
            width: 1
            height: 8 * root.s
            visible: !root.scanning && root.candidates.length > 0
        }

       Item {
           id: candidateViewport

           visible: !root.scanning && root.candidates.length > 0
           width: parent.width
           height: Math.min(candidateContent.implicitHeight, 420 * root.s)
           clip: true

           Flickable {
               id: candidateFlick

               anchors.left: parent.left
               anchors.top: parent.top
               anchors.bottom: parent.bottom
               anchors.right: scrollbarTrack.left
               anchors.rightMargin: 8 * root.s

               clip: true
               interactive: true
               boundsBehavior: Flickable.StopAtBounds

               contentWidth: width
               contentHeight: candidateContent.implicitHeight

               flickDeceleration: 1500
               maximumFlickVelocity: 2500

               Item {
                   id: candidateContent

                   width: candidateFlick.width
                   implicitHeight: candidatesColumn.implicitHeight

                   Column {
                       id: candidatesColumn

                       width: parent.width
                       spacing: 0

                       Repeater {
                           model: root.candidates
                           delegate: CandidateRow {}
                       }
                   }
               }
           }

           Rectangle {
               id: scrollbarTrack

               anchors.right: parent.right
               anchors.top: parent.top
               anchors.bottom: parent.bottom

               width: 6 * root.s
               radius: width / 2
               color: Theme.hairSoft
               opacity: 0.45

               visible: candidateFlick.contentHeight > candidateFlick.height
           }

           Rectangle {
               id: scrollbarThumb

               readonly property real scrollRange:
                   Math.max(0, candidateFlick.contentHeight - candidateFlick.height)

               readonly property real travel:
                   Math.max(0, scrollbarTrack.height - height)

               width: 6 * root.s

               height: Math.max(
                   30 * root.s,
                   scrollbarTrack.height *
                   candidateFlick.height /
                   Math.max(candidateFlick.contentHeight, 1)
               )

               x: scrollbarTrack.x
               y: scrollRange > 0
                   ? (candidateFlick.contentY / scrollRange) * travel
                   : 0

               radius: width / 2

               color: scrollbarMouse.pressed || scrollbarMouse.containsMouse
                   ? Theme.cream
                   : Theme.iconDim

               opacity: scrollbarTrack.visible ? 0.75 : 0

               Behavior on color {
                   ColorAnimation { duration: Motion.fast }
               }

               MouseArea {
                   id: scrollbarMouse

                   anchors.fill: parent
                   hoverEnabled: true
                   cursorShape: Qt.SizeVerCursor

                   property real grabOffset: 0

                   onPressed: {
                       grabOffset = mouseY
                   }

                   onPositionChanged: {
                       if (!pressed)
                           return

                       var nextY = scrollbarThumb.y + (mouseY - grabOffset)
                       nextY = Math.max(
                           0,
                           Math.min(scrollbarThumb.travel, nextY)
                       )

                       var fraction = scrollbarThumb.travel > 0
                           ? nextY / scrollbarThumb.travel
                           : 0

                       candidateFlick.contentY =
                           fraction * scrollbarThumb.scrollRange
                   }
               }
           }
       }

        Item {
            width: 1
            height: 14 * root.s
            visible: !root.scanning && root.candidates.length > 0
        }

        Row {
            visible: !root.scanning && root.candidates.length > 0
            width: parent.width
            spacing: 8 * root.s

            TextButton {
                id: selectAllButton
                label: "Select all"
                enabled: root.candidates.length > 0 &&
                         root.selectedCount < root.candidates.length
                onClicked: root.selectAll()
            }

            TextButton {
                id: clearButton
                label: "Clear"
                enabled: root.selectedCount > 0
                onClicked: root.clearSelection()
            }

            Item {
                width: Math.max(
                    0,
                    parent.width
                    - selectAllButton.implicitWidth
                    - clearButton.implicitWidth
                    - importButton.implicitWidth
                    - 16 * root.s
                )
                height: 1
            }

            TextButton {
                id: importButton
                label: root.selectedCount > 0
                    ? "Import " + root.selectedCount
                    : "Import"
                primary: true
                enabled: root.selectedCount > 0
                onClicked: root.importSelected()
            }
        }

        Item {
            width: 1
            height: 8 * root.s
        }
    }

    function importSelected() {
        var n = 0

        for (var i = 0; i < root.candidates.length; i++) {
            if (!root.checked[i])
                continue

            var c = root.candidates[i]

            if (c.source === "STEAM" &&
                !(c.steamAppId && c.steamAppId.length > 0)) {
                continue
            }

            var added = AppRegistry.add({
                name: c.name,
                category: c.category,
                runner: c.runner,
                executable: c.executable || "",
                sourcePath: c.sourcePath || "",
                gameFolder: c.gameFolder || c.installPath || "",
                candidateExecutables: Array.isArray(c.candidateExecutables) ? c.candidateExecutables : [],
                needsSetup: !!c.needsSetup,
                desktopEntryId: c.desktopEntryId || "",
                args: Array.isArray(c.args) ? c.args : [],
                prefix: c.prefix || "",
                steamAppId: c.steamAppId || "",
                protonBuild: c.protonBuild || "",
                env: c.env || {},
                workingDirectory: c.workingDirectory || ""
            })

            if (added)
                n++
        }

        root.imported(n)
    }
}
