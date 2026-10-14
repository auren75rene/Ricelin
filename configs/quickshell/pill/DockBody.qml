pragma ComponentBehavior: Bound

import QtQuick
import "Singletons"

/**
 * Everything the dock draws and does, with no window around it: the glass
 * capsule, the app slots, the status cluster, the sliding lens and the hint
 * bubble. DockLayer puts it in a layer-shell window and feeds it the network and
 * Bluetooth state; keeping those two out of here is what lets the offscreen
 * preview render it without Quickshell.
 *
 * The status buttons do not open anything of their own: they emit
 * `surfaceRequested` and the shell opens the pill's surface on this monitor.
 */
Item {
    id: root

    property real s: 1
    property string screenName: ""

    // Network and Bluetooth state, supplied by the window.
    property bool wifiPresent: false
    property bool wifiOn: false
    property real wifiLevel: 0
    property string wifiName: ""
    property bool btPresent: false
    property bool btOn: false

    signal surfaceRequested(string name)
    signal wifiToggled()
    signal btToggled()

    readonly property real edge: Dock.edgePx * s
    readonly property real pad: Dock.padPx * s
    readonly property real tile: Dock.tilePx * s
    readonly property real gap: 4 * s
    // Extra separation before the app/status divider keeps the settled Writer
    // focus outline and its border clear of the line.
    readonly property real dividerClearance: 5 * s
    // Extra vertical breathing room keeps the orbiting beads away from adjacent
    // app focus frames and from the capsule's rounded ends.
    readonly property real orbitRoom: 12 * s
    readonly property real sidePad: Dock.sidePadPx * s
    readonly property real bodyW: tile + 2 * sidePad
    /** Room to the right of the capsule for the hint bubble. */
    readonly property real hintRoom: 300 * s

    /** The only part of the strip that takes input. */
    readonly property rect capsule: Qt.rect(body.x, body.y, body.width, body.height)

    /** How many app slots fit above the cluster on this screen. */
    readonly property int maxApps: Math.max(1, Math.floor((height - 2 * edge - 2 * pad - tail.height - gap - root.dividerClearance) / (tile + gap)))

    // ---- hover: one lens, one hint ---------------------------------------------

    property Item lensTarget: null
    property real lensX: 0
    property real lensY: 0
    property real lensW: 0
    property real lensH: 0
    property bool lensContracting: false

    property string hintTitle: ""
    property string hintDesc: ""
    property real hintY: 0
    property bool hintShown: false

    function hover(target, on, title, desc) {
        if (!on) {
            if (root.lensTarget === target) {
                root.hintShown = false;
                hintDelay.stop();
                lensContractionDelay.stop();

                // Keep the lens visible for the full contraction, then fade it.
                // A new hover interrupts this and expands the same lens elsewhere.
                var centerX = root.lensX + root.lensW / 2;
                var centerY = root.lensY + root.lensH / 2;
                var collapsedSize = 8 * root.s;
                root.lensContracting = true;
                root.lensX = centerX - collapsedSize / 2;
                root.lensY = centerY - collapsedSize / 2;
                root.lensW = collapsedSize;
                root.lensH = collapsedSize;
                root.lensTarget = null;
                lensContractionDelay.restart();
            }
            return;
        }
        lensContractionDelay.stop();
        root.lensContracting = false;
        var p = target.mapToItem(body, 0, 0);
        var isAppIcon = !!target.item;
        // Every dock cell is the same size; app focus gets a little visual inset,
        // while status controls use the full cell without extra padding.
        var inflate = (isAppIcon ? 4 : 0) * root.s;

        // App focus hugs the glyph, not the whole clickable tile. The window
        // beads orbit outside this compact frame and keep their own hit targets.
        // Fixed proportion of the tile, never the artwork's glyph bounds: this
        // gives small fallback monograms a proper ~48 px focus layer at 1200p.
        var focusSize = isAppIcon ? target.tile * 0.82 : 0;
        var focusOffsetX = isAppIcon ? (target.width - focusSize) / 2 : 0;
        var focusOffsetY = isAppIcon ? (target.height - focusSize) / 2 : 0;

        root.lensTarget = target;
        root.lensX = p.x + focusOffsetX - inflate;
        root.lensY = p.y + focusOffsetY - inflate;
        root.lensW = isAppIcon ? focusSize + 2 * inflate : target.width + 2 * inflate;
        root.lensH = isAppIcon ? focusSize + 2 * inflate : target.height + 2 * inflate;
        root.hintTitle = title;
        root.hintDesc = desc;
        var faceOffsetY = target.faceVerticalOffset !== undefined
            ? target.faceVerticalOffset * target.s : 0;
        root.hintY = target.mapToItem(content, 0, target.height / 2 + faceOffsetY).y;
        // Already showing one hint: move to the next at once; otherwise wait a beat.
        if (root.hintShown)
            return;
        hintDelay.restart();
    }

    Timer {
        id: hintDelay
        interval: 320
        onTriggered: if (root.lensTarget) root.hintShown = true
    }

    Timer {
        id: lensContractionDelay
        interval: Motion.glide
        onTriggered: root.lensContracting = false
    }

    Item {
        id: content
        anchors.fill: parent

        Glass {
            id: body
            x: Dock.onRight ? content.width - root.edge - root.bodyW : root.edge
            y: Math.max(root.edge, (content.height - height) / 2)
            width: root.bodyW
            height: stack.implicitHeight + 2 * root.pad + 2 * root.orbitRoom
            radius: 30 * root.s
            clarity: 0.36

            // The lens: a soft pill of light that glides to the hovered item.
            Rectangle {
                id: lens
                x: root.lensX
                y: root.lensY
                width: root.lensW
                height: root.lensH
                radius: Math.min(root.lensTarget && root.lensTarget.item ? 19.5 * root.s : 16 * root.s, width / 2, height / 2)
                color: "transparent"
                gradient: Gradient {
                    GradientStop { position: 0; color: Qt.alpha(Theme.bright, 0.15) }
                    GradientStop { position: 0.36; color: Qt.alpha(Theme.bright, 0.055) }
                    GradientStop { position: 1; color: Qt.alpha(Theme.cardBot, 0.12) }
                }
                border.width: 1
                border.color: Qt.alpha(Theme.bright, 0.24)
                opacity: root.lensTarget || root.lensContracting ? 1 : 0
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                Behavior on x { enabled: lens.opacity > 0.05; NumberAnimation { duration: Motion.glide; easing.type: Easing.OutCubic } }
                Behavior on y { enabled: lens.opacity > 0.05; NumberAnimation { duration: Motion.glide; easing.type: Easing.OutCubic } }
                Behavior on width { enabled: lens.opacity > 0.05; NumberAnimation { duration: Motion.glide; easing.type: Easing.OutCubic } }
                Behavior on height { enabled: lens.opacity > 0.05; NumberAnimation { duration: Motion.glide; easing.type: Easing.OutCubic } }

            }

            Column {
                id: stack
                x: root.sidePad
                y: root.pad + root.orbitRoom
                width: root.tile
                // Preserve a deliberate clear zone below Writer before the
                // divider, including while the shared focus lens contracts.
                spacing: root.gap + root.dividerClearance

                // Pinned and running apps. Delegates are keyed by slot, not by app,
                // so a focus change or a new window never rebuilds the whole list.
                Column {
                    id: apps
                    // Stay on the same centreline as the status controls.
                    // Pip clearance is provided by the capsule's symmetric
                    // padding, never by shifting the app column.
                    width: parent.width
                    spacing: root.gap

                    Repeater {
                        model: Math.min(Dock.items.length, root.maxApps)

                        DockItem {
                            id: app
                            required property int index
                            item: Dock.items[app.index] || null
                            s: root.s
                            tile: root.tile
                            onActivated: Dock.activate(app.item, root.screenName)
                            onWindowActivated: (windowIndex) => Dock.activateWindow(app.item, windowIndex, root.screenName)
                            onLaunchNew: Dock.launch(app.item)
                            onPinToggled: Dock.togglePin(app.item)
                            onHoverChanged: (on) => root.hover(app, on, app.title, app.desc)
                        }
                    }
                }

                Column {
                    id: tail
                    width: parent.width
                    spacing: root.gap

                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: root.tile * 0.46
                        height: 1
                        color: Theme.hair
                    }

                    Column {
                        id: cluster
                        width: parent.width
                        // Use the same pitch as app cells so the dock reads as
                        // one measured rhythm from top to bottom.
                        spacing: root.gap

                        DockButton {
                            id: wifiBtn
                            visible: root.wifiPresent
                            s: root.s
                            tile: root.tile
                            wifi: true
                            wifiLevel: root.wifiLevel
                            wifiOn: root.wifiOn
                            onClicked: root.surfaceRequested("wifi")
                            onRightClicked: root.wifiToggled()
                            onHoverChanged: (on) => root.hover(wifiBtn, on, "Wi-Fi",
                                (!root.wifiOn ? "Off" : (root.wifiName.length > 0 ? root.wifiName : "Not connected")) + "  ·  Right-click to switch")
                        }

                        DockButton {
                            id: btBtn
                            visible: root.btPresent
                            s: root.s
                            tile: root.tile
                            glyph: "bluetooth"
                            tint: Peripherals.connectedCount > 0 ? Theme.vermLit
                                : (root.btOn ? Theme.iconDim : Qt.alpha(Theme.iconDim, 0.4))
                            onClicked: root.surfaceRequested("bt")
                            onRightClicked: root.btToggled()
                            onHoverChanged: (on) => root.hover(btBtn, on, "Bluetooth",
                                (!root.btOn ? "Off" : (Peripherals.connectedCount > 0 ? Peripherals.connectedCount + " connected" : "On")) + "  ·  Right-click to switch")
                        }

                        DockButton {
                            id: batteryBtn
                            visible: Battery.present
                            s: root.s
                            tile: root.tile
                            faceVerticalOffset: -4
                            glyph: "battery"
                            caption: Battery.pct + "%"
                            tint: Battery.low ? Theme.vermLit : (Battery.charging ? Theme.flameGlow : Theme.iconDim)
                            onClicked: root.surfaceRequested("battery")
                            onHoverChanged: (on) => root.hover(batteryBtn, on, "Battery",
                                Battery.stateLabel + (Battery.hasTime ? "  ·  " + Battery.timeStr : ""))
                        }

                        DockButton {
                            id: inboxBtn
                            s: root.s
                            tile: root.tile
                            glyph: "inbox"
                            badge: Notifs.unread > 0
                            onClicked: root.surfaceRequested("link")
                            onHoverChanged: (on) => root.hover(inboxBtn, on, "Notifications",
                                Notifs.unread > 0 ? Notifs.unread + " unread" : "Nothing new")
                        }

                        DockButton {
                            id: mixerBtn
                            s: root.s
                            tile: root.tile
                            glyph: "mixer"
                            onClicked: root.surfaceRequested("mixer")
                            onHoverChanged: (on) => root.hover(mixerBtn, on, "Sound & display", "Volume, mic, brightness, vibrance, keyboard light")
                        }

                        DockButton {
                            id: sysBtn
                            s: root.s
                            tile: root.tile
                            glyph: "monitor"
                            onClicked: root.surfaceRequested("sysmon")
                            onHoverChanged: (on) => root.hover(sysBtn, on, "System", "CPU, GPU, memory and storage")
                        }
                    }

                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: root.tile * 0.46
                        height: 1
                        color: Theme.hair
                    }

                    DockButton {
                        id: gridBtn
                        s: root.s
                        tile: root.tile
                        tileHeight: root.tile
                        glyph: "grid"
                        tint: Theme.cream
                        onClicked: root.surfaceRequested("launcher")
                        onHoverChanged: (on) => root.hover(gridBtn, on, "All apps", "Search and launch anything")
                    }
                }
            }
        }

        Text {
            anchors.horizontalCenter: body.horizontalCenter
            anchors.bottom: body.top
            anchors.bottomMargin: 8 * root.s
            width: 280 * root.s
            visible: Dock.loadError.length > 0
            text: Dock.loadError
            color: Theme.vermLit
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            font.family: Theme.font
            font.pixelSize: 10.5 * root.s
        }

        // The hint bubble: follows the lens, sits on the room side of the capsule.
        Item {
            id: hint
            x: Dock.onRight ? body.x - 12 * root.s - width : root.edge + root.bodyW + 12 * root.s
            y: root.hintY - height / 2
            width: hintGlass.width
            height: hintGlass.height
            opacity: root.hintShown ? 1 : 0
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: root.hintShown ? Motion.standard : Motion.fast } }
            Behavior on y { enabled: root.hintShown; NumberAnimation { duration: Motion.glide; easing.type: Easing.OutCubic } }

            Glass {
                id: hintGlass
                width: Math.min(root.hintRoom - 24 * root.s, Math.max(hintTitleText.implicitWidth, hintDescText.implicitWidth) + 28 * root.s)
                height: hintColumn.implicitHeight + 18 * root.s
                radius: 13 * root.s
                clarity: 0.55

                Column {
                    id: hintColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 14 * root.s
                    anchors.rightMargin: 14 * root.s
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2 * root.s

                    Text {
                        id: hintTitleText
                        width: parent.width
                        text: root.hintTitle
                        color: Theme.bright
                        font.family: Theme.font
                        font.pixelSize: 13 * root.s
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    Text {
                        id: hintDescText
                        width: parent.width
                        visible: text.length > 0
                        text: root.hintDesc
                        color: Theme.subtle
                        font.family: Theme.font
                        font.pixelSize: 10.5 * root.s
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }
}
