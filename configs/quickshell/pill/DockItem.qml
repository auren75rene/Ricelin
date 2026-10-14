pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "Singletons"

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
        anchors.fill: parent
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

    // Mean anomaly advances uniformly while this app is focused. Each dot's
    // position is derived by solving Kepler's equation for an elliptical orbit:
    // it naturally travels faster near periapsis and slower near apoapsis.
    property real orbitMeanAnomaly: 0

    NumberAnimation on orbitMeanAnomaly {
        from: 0
        to: 2 * Math.PI
        duration: 2400
        loops: Animation.Infinite
        running: !!(root.item && root.item.active)
    }

    function solveEccentricAnomaly(meanAnomaly, eccentricity) {
        var tau = 2 * Math.PI;
        var m = meanAnomaly % tau;
        if (m < 0)
            m += tau;

        var e = Math.max(0, Math.min(0.8, eccentricity));
        var estimate = m;
        for (var i = 0; i < 5; i++)
            estimate -= (estimate - e * Math.sin(estimate) - m)
                / (1 - e * Math.cos(estimate));
        return estimate;
    }

    // A dot per open window (up to three). On focus they orbit the icon as a
    // small planetary system; on blur they ease back to their static pip rail.
    Item {
        id: pips
        anchors.fill: parent
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
                readonly property real eccentricity: 0.10
                readonly property real semiMajorAxis: 19.5 * root.s
                readonly property real semiMinorAxis:
                    semiMajorAxis * Math.sqrt(1 - eccentricity * eccentricity)
                readonly property real phase:
                    2 * Math.PI * index / Math.max(1, dotCount)
                readonly property real eccentricAnomaly:
                    root.solveEccentricAnomaly(root.orbitMeanAnomaly + phase, eccentricity)

                readonly property real staticX:
                    (Dock.onRight ? root.width + 1.5 * root.s : -1.5 * root.s)
                    - width / 2
                readonly property real staticY:
                    root.height / 2
                    + (index - (dotCount - 1) / 2) * 10 * root.s
                    - height / 2

                readonly property real orbitX:
                    root.width / 2
                    + semiMajorAxis * (Math.cos(eccentricAnomaly) - eccentricity)
                    - width / 2
                readonly property real orbitY:
                    root.height / 2
                    + semiMinorAxis * Math.sin(eccentricAnomaly)
                    - height / 2

                property real orbitMix: root.item && root.item.active ? 1 : 0
                Behavior on orbitMix {
                    NumberAnimation {
                        duration: Motion.morph
                        easing.type: Motion.easeMorph
                        easing.bezierCurve: Motion.morphCurve
                    }
                }

                x: staticX + (orbitX - staticX) * orbitMix
                y: staticY + (orbitY - staticY) * orbitMix

                Rectangle {
                    anchors.centerIn: parent
                    width: pipHit.windowActive ? 5 * root.s : 4 * root.s
                    height: width
                    radius: width / 2
                    color: pipHit.windowActive
                        ? Theme.onGlow : Qt.alpha(Theme.cream, 0.7)
                    opacity: pipHit.windowRecord
                        && pipHit.windowRecord.workspace === "special:minimized" ? 0.45 : 1

                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width * 2.4
                        height: width
                        radius: width / 2
                        color: Qt.alpha(Theme.onGlow, 0.20)
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
