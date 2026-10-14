pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "Singletons"
import "lib/dock.js" as DockLib

/**
 * One app in the dock: its icon, a pip for every open window and a brighter pip
 * when one of them has focus. Left click brings the app forward (or starts it),
 * middle click starts another instance, right click pins or unpins it.
 *
 * The icon springs towards the pointer with the same tuning the app tiles use.
 * The hover backing is not drawn here: the dock slides one shared lens under
 * whichever item the pointer is on, so this item only reports hover.
 *
 * `item` is a record from lib/dock.js (id, name, icon, cls, pinned, running,
 * active, minimized).
 */
Item {
    id: root

    property var item: null
    property real s: 1
    property real tile: 44 * s

    signal activated()
    signal windowActivated(int index)
    signal launchNew()
    signal pinToggled()
    signal hoverChanged(bool on)

    readonly property bool hovered: area.containsMouse
    readonly property string title: item ? item.name : ""
    readonly property string desc: {
        if (!item)
            return "";
        var parts = [];
        if (item.running > 1) {
            parts.push(item.running + " windows");
            parts.push("Click a pip to focus that window");
        } else if (item.running === 1) {
            parts.push(item.minimized ? "Minimized" : "Open");
        }
        parts.push("Right-click to " + (item.pinned ? "unpin" : "pin"));
        return parts.join("  ·  ");
    }

    width: tile
    height: tile

    // New windows grow in instead of popping.
    scale: 0.6
    opacity: 0
    Component.onCompleted: enter.start()
    ParallelAnimation {
        id: enter
        NumberAnimation { target: root; property: "scale"; to: 1; duration: Motion.standard; easing.type: Easing.OutBack; easing.overshoot: 1.4 }
        NumberAnimation { target: root; property: "opacity"; to: 1; duration: Motion.fast }
    }

    // Focused app: a quiet fill only. The shared hover lens in DockBody
    // owns the single visible outline, so an active icon never gets a nested
    // border when the pointer moves over it. The active pip still marks focus.
    Rectangle {
        // Keep the persistent active-state tint as compact as the shared lens.
        // This is fill only; DockBody remains the sole owner of the outline.
        anchors.centerIn: iconBox
        width: iconBox.width + 14 * root.s
        height: width
        radius: 15 * root.s
        color: Qt.alpha(Theme.bright, 0.065)
        opacity: root.item && root.item.active ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Motion.fast } }
    }

    Item {
        id: iconBox
        anchors.centerIn: parent
        width: root.tile * 0.68
        height: width
        scale: area.pressed ? 0.9 : (area.containsMouse ? 1.16 : 1)
        Behavior on scale { SpringAnimation { spring: 3.5; damping: 0.3 } }
        // Minimized and not-running apps are a touch quieter than open ones.
        opacity: root.item && root.item.running > 0 && !root.item.minimized ? 1 : (root.item && root.item.minimized ? 0.62 : 0.9)

        Text {
            anchors.centerIn: parent
            visible: !icon.visible
            text: root.title.length > 0 ? root.title.charAt(0).toUpperCase() : "?"
            color: Theme.cream
            font.family: Theme.font
            font.pixelSize: root.tile * 0.42
            font.weight: Font.DemiBold
        }

        Image {
            id: icon
            anchors.fill: parent
            sourceSize.width: Math.round(root.tile * 1.4)
            sourceSize.height: Math.round(root.tile * 1.4)
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            smooth: true
            visible: status === Image.Ready && source != ""
            source: {
                if (!root.item)
                    return "";
                var name = root.item.icon && root.item.icon.length > 0 ? root.item.icon : String(root.item.cls || "").toLowerCase();
                if (name.length === 0)
                    return "";
                if (name.indexOf("/") === 0)
                    return "file://" + name;
                return Quickshell.iconPath(name, true);
            }
        }
    }

    // Hover triggers one orbital flourish, not a perpetual animation. The
    // first 250 ms accelerate hard; the final leg decelerates into a quiet orbit.
    // The dots stay around the icon while hovered and return to the outer rail
    // when the pointer leaves.
    property real orbitBurstProgress: 0

    SequentialAnimation {
        id: orbitBurst
        NumberAnimation {
            target: root
            property: "orbitBurstProgress"
            from: 0
            to: 0.41
            duration: 250
            easing.type: Easing.InCubic
        }
        NumberAnimation {
            target: root
            property: "orbitBurstProgress"
            from: 0.41
            to: 1
            duration: 360
            easing.type: Easing.OutCubic
        }
    }

    onHoveredChanged: {
        if (root.hovered && root.item && root.item.running > 0) {
            orbitBurst.stop();
            root.orbitBurstProgress = 0;
            orbitBurst.start();
        } else if (!root.hovered) {
            // Freeze the sweep where it is. orbitMix eases the dots back to
            // their rail, instead of snapping to the end of the orbit first.
            orbitBurst.stop();
        }
    }

    // A dot per open window (up to three). Cursor hover sends the dots through
    // one fast Kepler-style sweep, then leaves them parked around the icon.
    Item {
        id: pips
        // Extend beyond the tile so pip hit-targets remain valid at the outer
        // edge, even when their orbital position sits just outside the icon.
        x: -8 * root.s
        y: -8 * root.s
        width: root.width + 16 * root.s
        height: root.height + 16 * root.s
        visible: root.item && root.item.running > 0
        z: 2

        Repeater {
            model: root.item ? Math.min(3, root.item.running) : 0

            delegate: Item {
                id: pipHit
                required property int index
                width: 10 * root.s
                height: 10 * root.s

                readonly property int dotCount:
                    root.item ? Math.min(3, root.item.running) : 1
                readonly property var windowRecord:
                    root.item && root.item.windows && index < root.item.windows.length
                        ? root.item.windows[index] : null
                readonly property bool windowActive:
                    windowRecord && windowRecord.address === Dock.activeAddress
                readonly property real eccentricity: 0.05
                readonly property real semiMajorAxis: 18.5 * root.s
                readonly property real phase:
                    2 * Math.PI * index / Math.max(1, dotCount)
                readonly property var orbitalPosition:
                    DockLib.orbitPosition(
                        phase + root.orbitBurstProgress * 2 * Math.PI * 1.25,
                        semiMajorAxis, eccentricity)

                readonly property real staticX:
                    (Dock.onRight ? root.width + 1.5 * root.s : -1.5 * root.s)
                    - width / 2 + 8 * root.s
                readonly property real staticY:
                    root.height / 2
                    + (index - (dotCount - 1) / 2) * 10 * root.s
                    - height / 2 + 8 * root.s

                readonly property real orbitX:
                    root.width / 2 + orbitalPosition.x - width / 2 + 8 * root.s
                readonly property real orbitY:
                    root.height / 2 + orbitalPosition.y - height / 2 + 8 * root.s

                property real orbitMix: root.hovered ? 1 : 0
                Behavior on orbitMix {
                    NumberAnimation {
                        duration: Motion.morph
                        easing.type: Motion.easeMorph
                        easing.bezierCurve: Motion.morphCurve
                    }
                }

                x: staticX + (orbitX - staticX) * orbitMix
                y: staticY + (orbitY - staticY) * orbitMix

                // Tiny glass bead: tinted core, darkened lower edge, bright rim,
                // a specular catchlight and a restrained halo for focused windows.
                Rectangle {
                    id: bead
                    anchors.centerIn: parent
                    width: pipHit.windowActive ? 5 * root.s : 4 * root.s
                    height: width
                    radius: width / 2
                    gradient: Gradient {
                        GradientStop {
                            position: 0
                            color: pipHit.windowActive
                                ? Qt.lighter(Theme.onGlow, 1.65) : Qt.alpha(Theme.bright, 0.98)
                        }
                        GradientStop {
                            position: 0.42
                            color: pipHit.windowActive
                                ? Theme.onGlow : Qt.alpha(Theme.cream, 0.76)
                        }
                        GradientStop {
                            position: 1
                            color: pipHit.windowActive
                                ? Qt.darker(Theme.onGlow, 1.45) : Qt.alpha(Theme.subtle, 0.62)
                        }
                    }
                    border.width: 0.7 * root.s
                    border.color: Qt.alpha(Theme.bright, pipHit.windowActive ? 0.92 : 0.48)
                    opacity: pipHit.windowRecord
                        && pipHit.windowRecord.workspace === "special:minimized" ? 0.45 : 1

                    // The glint is deliberately offset; a centered flat dot reads
                    // like paint, while this reads as a tiny lens catching light.
                    Rectangle {
                        x: parent.width * 0.18
                        y: parent.height * 0.16
                        width: parent.width * 0.42
                        height: Math.max(0.8 * root.s, parent.height * 0.24)
                        radius: height / 2
                        color: Qt.alpha(Theme.bright, pipHit.windowActive ? 0.96 : 0.72)
                    }

                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width * 2.5
                        height: width
                        radius: width / 2
                        color: Qt.alpha(Theme.onGlow, 0.18)
                        visible: pipHit.windowActive
                        z: -1
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.windowActivated(pipHit.index)
                }
            }
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onContainsMouseChanged: root.hoverChanged(containsMouse)
        onClicked: (e) => {
            if (e.button === Qt.RightButton)
                root.pinToggled();
            else if (e.button === Qt.MiddleButton)
                root.launchNew();
            else
                root.activated();
        }
    }
}
