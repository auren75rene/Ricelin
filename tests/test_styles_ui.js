// Regression checks for the Styles & Persona UI and registration workflow.
"use strict";
const assert = require("assert");
const fs = require("fs");
const path = require("path");
const root = path.join(__dirname, "..", "configs", "quickshell", "pill");
const read = (name) => fs.readFileSync(path.join(root, name), "utf8");
const settings = read("Settings.qml");
const styles = read("StylesSurface.qml");
const addStyle = read("AddStyleSheet.qml");
const labeledField = read("LabeledField.qml");
const stylesSingleton = read("Singletons/Styles.qml");
const pill = read("Pill.qml");
const styleManager = fs.readFileSync(path.join(__dirname, "..", "configs", "hypr", "scripts", "ricelin-style"), "utf8");

function check(name, fn) {
    try { fn(); console.log("  ok   " + name); }
    catch (e) { console.error("  FAIL " + name + "\n         " + e.message); process.exitCode = 1; }
}

check("Settings index exposes Styles & Persona", () => {
    assert(settings.includes('{ item: stylesRow, kind: "nav", surface: "styles" }'));
    assert(settings.includes('name: "Styles & Persona"'));
    assert(settings.includes('sub: "Persona and other Quickshell themes"'));
    assert(settings.includes('icon: "palette"'));
});

check("the original palette shortcut still opens the same surface", () => {
    assert(pill.includes('onClicked: pill.requestSurface("styles")'));
    assert(pill.includes('readonly property bool stylesOpen: surface === "styles"'));
});

check("Styles surface labels Persona and shows a back affordance", () => {
    assert(styles.includes('text: "STYLES & PERSONA"'));
    assert(styles.includes('name: "chevron-left"'));
    assert(styles.includes("for (var i = 0; i < Styles.list.length; i++)"));
    assert(styles.includes("Styles.choose(r.id)"));
});

check("Styles includes an Add style row and form", () => {
    assert(styles.includes('name: "Add style"'));
    assert(styles.includes('kind: "add"'));
    assert(styles.includes("addSheet.reset()"));
    assert(styles.includes("root.adding = true"));
    assert(addStyle.includes('label: root.entryType === "config" ? "Config folder" : "Entry file"'));
    assert(addStyle.includes("AppLauncher") === false);
    assert(labeledField.includes("AppLauncher.pickFolder(cb)"));
    assert(labeledField.includes("AppLauncher.pickFile(cb)"));
    assert(addStyle.includes("Styles.registerStyle"));
    assert(stylesSingleton.includes('root.run(["add", id, name, kind, target, note || ""])'));
});

check("style registration is validated by the shared CLI", () => {
    assert(styleManager.includes("cmd_add() {"));
    assert(styleManager.includes('case "$new_kind" in config | path)'));
    assert(styleManager.includes('[ -d "$new_target" ] && [ -f "$new_target/shell.qml" ]'));
    assert(styleManager.includes('tmp="$conf_dir/.$new_id.conf.$$"'));
    assert(!styleManager.includes('eval "'));
});

check("Persona discovery honours the same custom path as qs-toggle", () => {
    assert(styleManager.includes('"$qs_dir"/*/'));
    assert(styleManager.includes('[ -f "${d}shell.qml" ] || continue'));
    assert(styleManager.includes('f="$conf_dir/$1.conf"'));
    assert(styleManager.includes("RICELIN_PERSONA_DIR"));
    assert(styleManager.includes('[ -f "$persona_dir/shell.qml" ]'));
    assert(styleManager.includes('target="$persona_dir"'));
    assert(styleManager.includes('cmd_list() {'));
});

check("recovery snapshots are hidden rather than offered as themes", () => {
    assert(styleManager.includes("pill-recovery-*) continue ;;"));
});

check("the Styles header returns to Settings instead of dismissing the pill", () => {
    const start = pill.indexOf("function surfaceBack()");
    const back = pill.slice(start, start + 1800);
    assert(back.includes("|| pill.stylesOpen)"));
    assert(back.includes('pill.requestSurface("settings")'));
});

if (!process.exitCode) console.log("\nall Styles UI checks passed");
