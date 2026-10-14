pragma ComponentBehavior: Bound

import QtQuick
import "Singletons"

/**
 * 装 STYLES surface: where the look is chosen. The first row opens the wallpaper
 * strip (the palette follows the wallpaper). Below it, "Ricelin" is the plain
 * setup and every other row is a style from ricelin-style (Persona and whatever
 * else is dropped into ~/.config/quickshell). Picking one stops the others and
 * starts it; picking the running one returns to plain Ricelin.
 *
 * Keys: Up and Down move, Enter picks.
 */
PillSurface {
    id: root

    mTop: 16
    mLeft: 19
    mRight: 19
    mBottom: 16

    property bool adding: false

    implicitHeight: root.adding ? addSheet.implicitHeight : content.implicitHeight

    /** Asks the pill to show another surface (the wallpaper strip). */
    signal requestSurface(string name)

    property int cursor: 0

    /** Row records in display order: the wallpaper link, plain Ricelin, then each style. */
    readonly property var rows: {
        var out = [
            { kind: "wallpaper", id: "", name: "Wallpapers", sub: "Pick a wallpaper; the colors follow it", glyph: "palette", active: false },
            { kind: "style", id: "ricelin", name: "Ricelin", sub: Styles.active === "ricelin" ? "Active" : "The default look", glyph: "sparkles", active: Styles.active === "ricelin" }
        ];
        for (var i = 0; i < Styles.list.length; i++) {
            var st = Styles.list[i];
            out.push({
                kind: "style",
                id: st.id,
                name: st.name,
                sub: st.running ? "Active" : (st.note.length > 0 ? st.note : "Starts on top of Ricelin"),
                glyph: "layers",
                active: st.running
            });
        }
        out.push({
            kind: "add",
            id: "",
            name: "Add style",
            sub: "Register another Quickshell setup",
            glyph: "plus",
            active: false
        });
        return out;
    }

    function activate(i) {
        var r = root.rows[i];
        if (!r)
            return;
        if (r.kind === "wallpaper") {
            root.requestSurface("wallpaper");
        } else if (r.kind === "add") {
            addSheet.reset();
            root.adding = true;
        } else {
            Styles.choose(r.id);
        }
    }

    onOpenChanged: {
        if (open) {
            root.adding = false;
            root.cursor = 0;
            Styles.refresh();
            keys.forceActiveFocus();
        }
    }

    // Catch changes made elsewhere (the Persona keybind, a style that quit).
    Timer {
        interval: 2000
        repeat: true
        running: root.open
        onTriggered: Styles.refresh()
    }

    Item {
        id: keys
        anchors.fill: parent
        focus: root.open && !root.adding
        enabled: !root.adding
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Up) {
                root.cursor = Math.max(0, root.cursor - 1);
                event.accepted = true;
            } else if (event.key === Qt.Key_Down) {
                root.cursor = Math.min(root.rows.length - 1, root.cursor + 1);
                event.accepted = true;
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                root.activate(root.cursor);
                event.accepted = true;
            }
        }
    }

    Column {
        id: content
        width: parent.width
        spacing: 0
        visible: !root.adding

        Item {
            width: parent.width
            height: 24 * root.s

            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8 * root.s

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: Flags.showGlyphs
                    text: "装"
                    color: Theme.cream
                    font.family: Theme.fontJp
                    font.weight: Font.Medium
                    font.pixelSize: 16 * root.s
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "STYLES & PERSONA"
                    color: Theme.subtle
                    font.family: Theme.font
                    font.pixelSize: 10 * root.s
                    font.weight: Font.DemiBold
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: 1.6 * root.s
                }
            }

            // The pill routes header clicks through surfaceBack(); this arrow
            // makes the return path to Settings visible instead of implicit.
            GlyphIcon {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 16 * root.s
                height: 16 * root.s
                name: "chevron-left"
                color: Theme.iconDim
                stroke: 2.2
            }
        }

        Item { width: 1; height: 8 * root.s }

        Repeater {
            model: root.rows

            StyleRow {
                id: row
                required property var modelData
                required property int index
                s: root.s
                name: row.modelData.name
                sub: row.modelData.sub
                glyph: row.modelData.glyph
                active: row.modelData.active
                opens: row.modelData.kind === "wallpaper"
                selected: row.index === root.cursor
                last: row.index === root.rows.length - 1
                onActivated: {
                    root.cursor = row.index;
                    root.activate(row.index);
                }
            }
        }

        Text {
            width: parent.width
            topPadding: 8 * root.s
            visible: Styles.list.length === 0
            wrapMode: Text.WordWrap
            text: "No extra styles yet. Use Add style to register a Quickshell folder or entry file; its dotfiles stay where they are."
            color: Theme.faint
            font.family: Theme.font
            font.pixelSize: 10.5 * root.s
            lineHeight: 1.3
        }
    }

    AddStyleSheet {
        id: addSheet
        width: parent.width
        s: root.s
        visible: root.adding
        onCancelled: {
            root.adding = false;
            keys.forceActiveFocus();
        }
        onAdded: {
            root.adding = false;
            root.cursor = 0;
            Styles.refresh();
            keys.forceActiveFocus();
        }
    }
}
