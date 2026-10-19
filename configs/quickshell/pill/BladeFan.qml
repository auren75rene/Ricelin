pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import "Singletons"
import "lib/blades.js" as Blades

/**
 * The blade fan: a quarter-circle of guide rays and arcs growing out of the
 * top-left corner, with one capsule "blade" per game or Wine app laid along its
 * own ray like a spread hand of cards.
 *
 *        blade
 *          ───────────
 *        /
 *       /
 *      ◉────────────── blade
 *       \
 *        \
 *          ───────────
 *
 * This item only draws and reports clicks. When it opens, and where the pointer
 * is, is decided by the BladeLayer window around it; the apps come from a
 * BladeLauncherModel (anything with count, appAt, stateFor, labelFor and
 * launch(index) works, which is also how the offscreen preview drives it).
 */
Item {
    id: fan

    required property var model

    /** Overall scale, the same screen-height factor the pill uses. */
    property real s: 1
    /** Whether the fan should be open. The spread itself animates in `progress`. */
    property bool open: false

    signal toggleRequested()
    signal launched()

    readonly property real originX: 24 * s
    readonly property real originY: 24 * s
    readonly property real beadSize: 44 * s
    readonly property real fanStartRadius: 250 * s
    /** Maximum radial distance available on the physical output, in pixels. */
    property real availableRadius: 1000
    readonly property real ringGap: 16 * s
    readonly property real bladeHeight: 52 * s

    readonly property int count: model ? model.count : 0
    readonly property var layoutFit: Blades.fitLayout(
        count, 6, fanStartRadius, availableRadius, 255 * s, ringGap, 64 * s)
    readonly property int ringCount: layoutFit.ringCount
    readonly property var placements: layoutFit.placements
    readonly property real bladeLength: layoutFit.bladeLength
    readonly property real ringStep: layoutFit.ringStep
    readonly property real fanEndRadius: layoutFit.outerRadius
    readonly property real sectorSize: fanEndRadius + 24 * s
    /** How far from the origin the pointer still counts as "on the fan". */
    readonly property real reach: sectorSize + 30 * s
    /** Size of the square the fan needs: origin offset plus its reach. */
    readonly property real extent: originX + reach

    function placementAt(index) {
        return index >= 0 && index < fan.placements.length ? fan.placements[index] : null;
    }

    property real progress: open ? 1 : 0
    Behavior on progress {
        NumberAnimation {
            duration: Motion.morph
            easing.type: Motion.easeMorph
            easing.bezierCurve: Motion.morphCurve
        }
    }

    function fanAngle(index) {
        var p = fan.placementAt(index);
        return p ? p.angle : 43;
    }

    /** Stagger each balanced ring independently; the delay remains bounded for any number of games. */
    function bladeProgress(index) {
        var p = fan.placementAt(index);
        if (!p || p.ringSize <= 1)
            return progress;
        var lag = Math.min(0.07, 0.5 / (p.ringSize - 1));
        return Math.max(0, Math.min(1, (progress - lag * p.slot) / (1 - lag * (p.ringSize - 1))));
    }

    // Liquid-glass lens behind the fan. Its tint stays deliberately faint so
    // the compositor-blurred wallpaper shows through; the individual app blades
    // below keep their existing Glass styling and colors.
    Shape {
        visible: fan.progress > 0.002
        opacity: fan.progress
        anchors.fill: parent
        antialiasing: true
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            // The tint thickens a little as the fan settles open, then thins
            // again as progress reverses on close. This is a restrained material
            // morph, not a pulsing animation.
            strokeColor: Qt.alpha(Theme.cardBot, 0.30)
            strokeWidth: 2.0 * fan.s
            fillGradient: RadialGradient {
                centerX: fan.originX
                centerY: fan.originY
                centerRadius: fan.sectorSize
                focalX: fan.originX
                focalY: fan.originY
                GradientStop { position: 0; color: Qt.alpha(Theme.cardTop, 0.23 + 0.13 * fan.progress) }
                GradientStop { position: 0.58; color: Qt.alpha(Theme.cardTop, 0.08 + 0.06 * fan.progress) }
                GradientStop { position: 1; color: Qt.alpha(Theme.cardBot, 0.02 + 0.025 * fan.progress) }
            }
            startX: fan.originX
            startY: fan.originY
            PathLine { x: fan.originX + fan.sectorSize; y: fan.originY }
            PathArc {
                x: fan.originX
                y: fan.originY + fan.sectorSize
                radiusX: fan.sectorSize
                radiusY: fan.sectorSize
                direction: PathArc.Clockwise
            }
            PathLine { x: fan.originX; y: fan.originY }
        }

        // A brighter meniscus along the upper rim gives the pane a glass edge
        // without tinting the app blades themselves.
        ShapePath {
            // The clean, bright inner rim stays readable against light and
            // dark wallpapers; its slight increase follows the same open morph.
            strokeColor: Qt.alpha(Theme.bright, 0.52 + 0.16 * fan.progress)
            strokeWidth: 1.25 * fan.s
            fillColor: "transparent"
            startX: fan.originX
            startY: fan.originY
            PathLine { x: fan.originX + fan.sectorSize; y: fan.originY }
            PathArc {
                x: fan.originX
                y: fan.originY + fan.sectorSize
                radiusX: fan.sectorSize
                radiusY: fan.sectorSize
                direction: PathArc.Clockwise
            }
        }
    }

    // Concentric guide arcs.
    Repeater {
        model: Math.max(5, Math.ceil((fan.fanEndRadius / fan.s - 150) / 100) + 1)

        delegate: Shape {
            id: arc
            required property int index
            readonly property real r: (150 + 100 * index) * fan.s

            x: fan.originX - r
            y: fan.originY - r
            width: r * 2
            height: r * 2
            visible: fan.progress > 0.002
            opacity: 0.55 * fan.progress
            antialiasing: true

            ShapePath {
                strokeColor: Qt.alpha(Theme.cream, 0.20)
                strokeWidth: 1
                fillColor: "transparent"
                PathAngleArc {
                    centerX: arc.r
                    centerY: arc.r
                    radiusX: arc.r
                    radiusY: arc.r
                    startAngle: 0
                    sweepAngle: 90
                }
            }
        }
    }

    // Guide rays, one per blade.
    Repeater {
        model: fan.count

        delegate: Rectangle {
            id: ray
            required property int index

            x: fan.originX
            y: fan.originY - 0.5
            width: fan.fanEndRadius
            height: 1
            transformOrigin: Item.Left
            rotation: fan.fanAngle(0) + (fan.fanAngle(index) - fan.fanAngle(0)) * fan.bladeProgress(index)
            visible: fan.progress > 0.002
            opacity: 0.30 * fan.progress
            color: Theme.cream
        }
    }

    // Origin bead: the handle. Clicking it pins the fan open.
    Glass {
        id: bead
        x: fan.originX - width / 2
        y: fan.originY - height / 2
        width: fan.beadSize
        height: width
        radius: width / 2
        clarity: fan.open ? 0.42 : 0.5
        lit: fan.open

        GlyphIcon {
            anchors.centerIn: parent
            width: parent.width * 0.5
            height: width
            name: "gamepad"
            color: fan.open ? Theme.bright : Theme.iconDim
            stroke: 1.7
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: fan.toggleRequested()
        }
    }

    // The blades.
    Repeater {
        model: fan.count

        delegate: Item {
            id: blade
            required property int index

            readonly property var app: fan.model.appAt(index)
            readonly property var placement: fan.placementAt(index)
            readonly property string appState: fan.model.stateFor(index)
            readonly property real p: fan.bladeProgress(index)

            // Every ring unfolds symmetrically from its centre ray.
            readonly property real theta: 43 + (fan.fanAngle(index) - 43) * p
            readonly property real startRadius: fan.fanStartRadius + (placement ? placement.ring * fan.ringStep : 0)

            width: fan.bladeLength
            height: fan.bladeHeight
            x: fan.originX + Math.cos(theta * Math.PI / 180) * startRadius
            y: fan.originY + Math.sin(theta * Math.PI / 180) * startRadius - height / 2
            z: 100 + index
            visible: p > 0.002
            opacity: p
            rotation: theta
            transformOrigin: Item.Left

            property real grow: tap.pressed ? 0.985 : (hover.hovered ? 1.04 : 1)
            Behavior on grow { SpringAnimation { spring: 4; damping: 0.32 } }
            scale: grow

            Glass {
                anchors.fill: parent
                radius: height / 2
                clarity: hover.hovered ? 0.34 : 0.52
                lit: hover.hovered

                Rectangle {
                    id: tile
                    anchors.left: parent.left
                    anchors.leftMargin: 9 * fan.s
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.height - 18 * fan.s
                    height: width
                    radius: width / 2
                    color: Qt.alpha(Theme.tileBg, 0.85)
                    border.width: 1
                    border.color: Theme.hair

                    Text {
                        anchors.centerIn: parent
                        visible: !icon.visible
                        text: blade.app && blade.app.name.length > 0 ? blade.app.name.charAt(0).toUpperCase() : "?"
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: 15 * fan.s
                        font.weight: Font.DemiBold
                    }

                    Image {
                        id: icon
                        anchors.fill: parent
                        anchors.margins: 6 * fan.s
                        sourceSize.width: 64
                        sourceSize.height: 64
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        visible: status === Image.Ready && source != ""
                        source: blade.app && blade.app.iconImage && blade.app.iconImage.length > 0 ? "file://" + blade.app.iconImage : ""
                    }
                }

                Column {
                    anchors.left: tile.right
                    anchors.leftMargin: 11 * fan.s
                    anchors.right: dot.left
                    anchors.rightMargin: 8 * fan.s
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2 * fan.s

                    Text {
                        width: parent.width
                        text: blade.app ? blade.app.name : ""
                        color: Theme.cream
                        font.family: Theme.font
                        font.pixelSize: 13 * fan.s
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        text: {
                            var base = fan.model.labelFor(blade.index);
                            if (blade.appState === "running")
                                return base + "  ·  running";
                            if (blade.appState === "launching")
                                return base + "  ·  launching";
                            if (blade.appState === "waiting")
                                return "waiting for empty workspace";
                            if (blade.appState === "stopping")
                                return "stopping";
                            if (blade.appState === "failed")
                                return "needs attention";
                            return base;
                        }
                        color: blade.appState === "failed" ? Theme.vermLit
                            : (blade.appState === "idle" ? Theme.faint : Theme.flameGlow)
                        font.family: Theme.font
                        font.pixelSize: 10 * fan.s
                        font.weight: Font.Medium
                        elide: Text.ElideRight
                    }
                }

                Rectangle {
                    id: dot
                    anchors.right: parent.right
                    anchors.rightMargin: 16 * fan.s
                    anchors.verticalCenter: parent.verticalCenter
                    width: 8 * fan.s
                    height: width
                    radius: width / 2
                    visible: blade.appState !== "idle"
                    color: blade.appState === "failed" ? Theme.vermLit : Theme.onGlow
                    SequentialAnimation on opacity {
                        running: dot.visible
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.4; duration: Motion.pulse; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1; duration: Motion.pulse; easing.type: Easing.InOutSine }
                    }
                }
            }

            HoverHandler {
                id: hover
                cursorShape: Qt.PointingHandCursor
            }

            property bool tapPending: false

            // Delay single-click activation briefly so a double click has one
            // unambiguous meaning: stop (or cancel a queued launch).
            Timer {
                id: tapDisambiguation
                interval: 260
                onTriggered: {
                    blade.tapPending = false;
                    fan.model.launch(blade.index);
                    fan.launched();
                }
            }

            TapHandler {
                id: tap
                onTapped: {
                    if (blade.tapPending) {
                        tapDisambiguation.stop();
                        blade.tapPending = false;
                        fan.model.stop(blade.index);
                        fan.launched();
                    } else {
                        blade.tapPending = true;
                        tapDisambiguation.restart();
                    }
                }
            }
        }
    }
}
