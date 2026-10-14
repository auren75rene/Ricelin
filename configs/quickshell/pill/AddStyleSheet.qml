pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import "Singletons"

/**
 * Register an external Quickshell setup from the Styles surface.
 * It only records the selected config/entry path; it never copies or executes
 * the dotfiles. ricelin-style validates the path and writes the registration.
 */
Item {
    id: root

    property real s: 1
    property string entryType: "config"
    property string target: ""
    property string displayName: ""
    property string styleId: ""
    property string note: ""
    property string errorText: ""
    property bool syncingDefaults: false
    property bool nameTouched: false
    property bool idTouched: false
    property bool saving: false

    signal cancelled()
    signal added()

    width: parent ? parent.width : 0
    implicitHeight: col.implicitHeight

    readonly property bool canAdd: !root.saving
        && root.target.trim().length > 0
        && root.displayName.trim().length > 0
        && /^[a-z0-9._-]+$/.test(root.styleId.trim())
        && root.styleId !== "." && root.styleId !== ".."
        && ["ricelin", "pill", "launcher", "lock"].indexOf(root.styleId) < 0
        && !root.styleId.startsWith("pill-recovery-")

    function slugify(value) {
        return String(value).toLowerCase().replace(/-quickshell$/i, "")
            .replace(/[^a-z0-9._-]+/g, "-").replace(/^-+|-+$/g, "");
    }

    function baseName(value) {
        var clean = String(value).replace(/\/+$/, "");
        var parts = clean.split("/");
        var base = parts[parts.length - 1] || "";
        if (root.entryType === "path") {
            var dot = base.lastIndexOf(".");
            if (dot > 0) base = base.slice(0, dot);
        }
        return base.replace(/-quickshell$/i, "");
    }

    function reset() {
        root.entryType = "config";
        root.target = "";
        root.displayName = "";
        root.styleId = "";
        root.note = "";
        root.errorText = "";
        root.syncingDefaults = false;
        root.nameTouched = false;
        root.idTouched = false;
        root.saving = false;
    }

    function targetPicked(value) {
        if (!value || value.length === 0) return;
        root.target = value;
        var base = root.baseName(value);
        root.syncingDefaults = true;
        if (!root.nameTouched) root.displayName = base;
        if (!root.idTouched) root.styleId = root.slugify(root.nameTouched ? root.displayName : base);
        root.syncingDefaults = false;
        root.errorText = "";
    }

    function nameEdited(value) {
        root.displayName = value;
        if (root.syncingDefaults) return;
        root.nameTouched = true;
        if (!root.idTouched) {
            root.syncingDefaults = true;
            root.styleId = root.slugify(value);
            root.syncingDefaults = false;
        }
    }

    function submit() {
        if (!root.canAdd || Styles.busy) return;
        root.errorText = "";
        root.saving = true;
        Styles.registerStyle(root.styleId.trim(), root.displayName.trim(),
            root.entryType, root.target.trim(), root.note.trim());
    }

    Connections {
        target: Styles
        function onRegistrationFinished(succeeded) {
            if (!root.saving) return;
            root.saving = false;
            if (succeeded) root.added();
            else root.errorText = "Could not register this style. Check that its path is valid and its ID is unique.";
        }
    }

    component TextButton: Rectangle {
        id: tb
        property string label: ""
        property bool primary: false
        property bool available: true
        signal clicked()
        implicitWidth: tbLabel.implicitWidth + 22 * root.s
        implicitHeight: 32 * root.s
        radius: 9 * root.s
        color: tb.primary ? (tb.available ? Theme.vermDeep : Theme.threadBg) : (tbArea.containsMouse ? Theme.frameBg : "transparent")
        opacity: tb.available ? 1 : 0.5
        border.width: 1
        border.color: tb.primary ? "transparent" : Theme.frameBorder
        Behavior on color { ColorAnimation { duration: Motion.fast } }
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
            enabled: tb.available
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
                    color: backArea.containsMouse ? Theme.cream : Theme.iconDim
                    stroke: 2.2
                    MouseArea {
                        id: backArea
                        anchors.fill: parent
                        anchors.margins: -6 * root.s
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.cancelled()
                    }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "ADD A STYLE"
                    color: Theme.cream
                    font.family: Theme.font
                    font.pixelSize: 12.5 * root.s
                    font.weight: Font.Bold
                    font.letterSpacing: 1.1 * root.s
                }
            }
        }

        Item { width: 1; height: 12 * root.s }

        Text {
            width: parent.width
            text: "Register another Quickshell setup. Its files stay where they are."
            wrapMode: Text.WordWrap
            color: Theme.faint
            font.family: Theme.font
            font.pixelSize: 10.5 * root.s
            lineHeight: 1.25
        }

        Item { width: 1; height: 10 * root.s }

        SettingsRow {
            name: "Source"
            sub: root.entryType === "config" ? "Folder containing shell.qml" : "Single QML entry file"
            control: SettingsSeg {
                s: root.s
                compact: true
                options: [
                    { label: "Folder", value: "config" },
                    { label: "QML file", value: "path" }
                ]
                value: root.entryType
                onPicked: (value) => {
                    root.entryType = value;
                    root.target = "";
                    root.errorText = "";
                }
            }
        }

        Item { width: 1; height: 8 * root.s }

        LabeledField {
            id: targetField
            s: root.s
            label: root.entryType === "config" ? "Config folder" : "Entry file"
            text: root.target
            placeholder: root.entryType === "config" ? "Folder containing shell.qml" : "Path to the main QML file"
            browse: root.entryType === "config" ? "folder" : "qml"
            onTextChanged: root.target = text
            onCommitted: (value) => root.targetPicked(value)
        }

        Item { width: 1; height: 6 * root.s }

        LabeledField {
            s: root.s
            label: "Display name"
            text: root.displayName
            placeholder: "How it appears in Styles"
            onTextChanged: root.nameEdited(text)
        }

        Item { width: 1; height: 6 * root.s }

        LabeledField {
            s: root.s
            label: "Style ID"
            text: root.styleId
            placeholder: "lowercase-id"
            onTextChanged: {
                root.styleId = text;
                if (!root.syncingDefaults) root.idTouched = true;
            }
        }

        Item { width: 1; height: 6 * root.s }

        LabeledField {
            s: root.s
            label: "Description (optional)"
            text: root.note
            placeholder: "A short subtitle in the Styles list"
            last: true
            onTextChanged: root.note = text
        }

        Text {
            width: parent.width
            visible: root.errorText.length > 0
            topPadding: 8 * root.s
            text: root.errorText
            color: Theme.flameGlow
            wrapMode: Text.WordWrap
            font.family: Theme.font
            font.pixelSize: 10.5 * root.s
        }

        Item { width: 1; height: 12 * root.s }

        Row {
            anchors.right: parent.right
            spacing: 8 * root.s
            TextButton { label: "Cancel"; available: !root.saving; onClicked: root.cancelled() }
            TextButton {
                label: root.saving ? "Adding…" : "Add style"
                primary: true
                available: root.canAdd && !Styles.busy
                onClicked: root.submit()
            }
        }

        Item { width: 1; height: 8 * root.s }
    }
}
