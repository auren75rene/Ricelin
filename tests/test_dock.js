// Self-check for configs/quickshell/pill/lib/dock.js. The file is a QML
// `.pragma library`, so the pragma line is stripped and the rest runs in a vm.
// Run: node tests/test_dock.js
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");
const assert = require("assert");

const file = path.join(__dirname, "..", "configs", "quickshell", "pill", "lib", "dock.js");
const src = fs.readFileSync(file, "utf8").replace(/^\.pragma.*$/m, "");
const dockSingletonFile = path.join(__dirname, "..", "configs", "quickshell", "pill", "Singletons", "Dock.qml");
const dockSingletonSrc = fs.readFileSync(dockSingletonFile, "utf8");
const dockItemFile = path.join(__dirname, "..", "configs", "quickshell", "pill", "DockItem.qml");
const dockItemSrc = fs.readFileSync(dockItemFile, "utf8");
const dockButtonFile = path.join(__dirname, "..", "configs", "quickshell", "pill", "DockButton.qml");
const dockButtonSrc = fs.readFileSync(dockButtonFile, "utf8");
const dockBodyFile = path.join(__dirname, "..", "configs", "quickshell", "pill", "DockBody.qml");
const dockBodySrc = fs.readFileSync(dockBodyFile, "utf8");
const ctx = {};
vm.createContext(ctx);
vm.runInContext(src, ctx);
const D = ctx;

let failed = 0;
function check(name, fn) {
    try { fn(); console.log("  ok   " + name); }
    catch (e) { failed++; console.log("  FAIL " + name + "\n         " + e.message); }
}

const entries = [
    { id: "org.kde.dolphin", name: "Dolphin", icon: "system-file-manager", startupClass: "dolphin" },
    { id: "com.mitchellh.ghostty", name: "Ghostty", icon: "com.mitchellh.ghostty", startupClass: "" },
    { id: "firefox", name: "Firefox", icon: "firefox", startupClass: "firefox" },
    { id: "steam", name: "Steam", icon: "steam", startupClass: "Steam" },
    { id: "org.gnome.Calculator", name: "Calculator", icon: "calc", startupClass: "" },
];
const win = (address, cls, workspace) => ({ address, cls, title: cls + " window", workspace: workspace || "1" });
// Arrays built inside the vm have a different prototype; compare them as JSON.
const same = (a, b) => assert.strictEqual(JSON.stringify(a), JSON.stringify(b));
const ids = (items) => items.map((i) => i.id).join(",");

console.log("matchEntry");
check("exact id", () => assert.strictEqual(D.matchEntry("firefox", entries).id, "firefox"));
check("id is case-insensitive", () => assert.strictEqual(D.matchEntry("Firefox", entries).id, "firefox"));
check("id with .desktop", () => assert.strictEqual(D.matchEntry("firefox.desktop", entries).id, "firefox"));
check("startup class", () => assert.strictEqual(D.matchEntry("Steam", entries).id, "steam"));
check("last segment of a reverse-DNS id", () => assert.strictEqual(D.matchEntry("ghostty", entries).id, "com.mitchellh.ghostty"));
check("full reverse-DNS class", () => assert.strictEqual(D.matchEntry("org.kde.dolphin", entries).id, "org.kde.dolphin"));
check("name as the last resort", () => assert.strictEqual(D.matchEntry("calculator", entries).id, "org.gnome.Calculator"));
check("an exact id beats a looser rule", () => {
    const e = [
        { id: "org.example.term", name: "Other", icon: "", startupClass: "" },
        { id: "term", name: "Term", icon: "", startupClass: "" },
    ];
    assert.strictEqual(D.matchEntry("term", e).id, "term");
});
check("no match, empty class and missing list give null", () => {
    assert.strictEqual(D.matchEntry("cyberpunk2077.exe", entries), null);
    assert.strictEqual(D.matchEntry("", entries), null);
    assert.strictEqual(D.matchEntry("x", null), null);
});

console.log("build");
check("pinned apps come first, in pinned order, even when not running", () => {
    const items = D.build(["firefox", "org.kde.dolphin"], [], entries, "");
    assert.strictEqual(ids(items), "firefox,org.kde.dolphin");
    assert.ok(items.every((i) => i.pinned && i.running === 0));
});
check("running unpinned apps follow, in first-window order", () => {
    const ws = [win("0x2", "steam"), win("0x1", "ghostty")];
    const items = D.build(["firefox"], ws, entries, "");
    assert.strictEqual(ids(items), "firefox,steam,com.mitchellh.ghostty");
    assert.ok(!items[1].pinned);
});
check("windows of one app are grouped under it", () => {
    const ws = [win("0x1", "firefox"), win("0x2", "dolphin"), win("0x3", "firefox")];
    const items = D.build(["firefox"], ws, entries, "");
    assert.strictEqual(items[0].running, 2);
    assert.strictEqual(items[1].running, 1);
});
check("a pinned app's windows attach to the pinned item", () => {
    const items = D.build(["org.kde.dolphin"], [win("0x1", "dolphin")], entries, "");
    assert.strictEqual(items.length, 1);
    assert.strictEqual(items[0].running, 1);
    assert.ok(items[0].pinned);
});
check("a window with no desktop entry gets its own item", () => {
    const items = D.build([], [win("0x9", "cyberpunk2077.exe")], entries, "");
    assert.strictEqual(items.length, 1);
    assert.strictEqual(items[0].id, "cyberpunk2077.exe");
    assert.strictEqual(items[0].icon, "");
    assert.strictEqual(items[0].cls, "cyberpunk2077.exe");
    assert.ok(!items[0].installed);
});
check("a pinned app that is not installed and not running is hidden", () => {
    const items = D.build(["gone-app", "firefox"], [], entries, "");
    assert.strictEqual(ids(items), "firefox");
});
check("a duplicate pin is listed once", () => {
    const items = D.build(["firefox", "Firefox.desktop"], [], entries, "");
    assert.strictEqual(items.length, 1);
});
check("the focused window marks its app active", () => {
    const ws = [win("0x1", "firefox"), win("0x2", "dolphin")];
    const items = D.build([], ws, entries, "0x2");
    assert.ok(!items[0].active);
    assert.ok(items[1].active);
});
check("an app with only minimized windows reads as minimized", () => {
    const items = D.build([], [win("0x1", "firefox", "special:minimized")], entries, "");
    assert.ok(items[0].minimized);
    const mixed = D.build([], [win("0x1", "firefox", "special:minimized"), win("0x2", "firefox", "2")], entries, "");
    assert.ok(!mixed[0].minimized);
});
check("windows without a class are ignored", () => {
    assert.strictEqual(D.build([], [win("0x1", "")], entries, "").length, 0);
});
check("null inputs give an empty dock", () => assert.strictEqual(D.build(null, null, null, "").length, 0));
check("build never changes the inputs", () => {
    const pinned = ["firefox"];
    const ws = [win("0x1", "firefox")];
    D.build(pinned, ws, entries, "");
    same(pinned, ["firefox"]);
    assert.strictEqual(ws.length, 1);
});

console.log("Kepler orbital motion");
check("eccentric anomaly satisfies Kepler's equation", () => {
    const tau = 2 * Math.PI;
    for (const eccentricity of [0, 0.1, 0.4]) {
        for (const mean of [0, 0.25, 1.7, Math.PI, 5.8]) {
            const E = D.solveEccentricAnomaly(mean, eccentricity);
            const M = ((mean % tau) + tau) % tau;
            assert.ok(Math.abs(E - eccentricity * Math.sin(E) - M) < 1e-10,
                "Kepler residual too large for e=" + eccentricity + ", M=" + mean);
        }
    }
});
check("orbital position reaches periapsis and apoapsis", () => {
    const peri = D.orbitPosition(0, 20, 0.1);
    const apo = D.orbitPosition(Math.PI, 20, 0.1);
    assert.ok(Math.abs(peri.x - 18) < 1e-10);
    assert.ok(Math.abs(peri.y) < 1e-10);
    assert.ok(Math.abs(apo.x + 22) < 1e-10);
    assert.ok(Math.abs(apo.y) < 1e-10);
});
check("cursor hover triggers a finite acceleration/deceleration orbit", () => {
    assert.ok(dockItemSrc.includes("property real orbitBurstProgress: 0"));
    assert.ok(dockItemSrc.includes("onHoveredChanged: {"));
    assert.ok(dockItemSrc.includes("root.hovered && root.item && root.item.running > 0"));
    assert.ok(dockItemSrc.includes("duration: 250"));
    assert.ok(dockItemSrc.includes("to: 0.41"));
    assert.ok(dockItemSrc.includes("easing.type: Easing.InCubic"));
    assert.ok(dockItemSrc.includes("from: 0.41"));
    assert.ok(dockItemSrc.includes("duration: 360"));
    assert.ok(dockItemSrc.includes("easing.type: Easing.OutCubic"));
    assert.ok(dockItemSrc.includes("property real orbitMix: root.hovered ? 1 : 0"));
    assert.ok(dockItemSrc.includes("DockLib.orbitPosition("));
    assert.ok(dockItemSrc.includes("root.windowActivated(pipHit.index)"));
    assert.ok(!dockItemSrc.includes("Animation.Infinite"), "hover effect must not rotate forever");
    assert.ok(!dockItemSrc.includes("orbitMeanAnomaly"), "continuous orbital animation should be removed");
});
check("window beads return smoothly when the cursor leaves", () => {
    assert.ok(dockItemSrc.includes("Freeze the sweep where it is"));
    assert.ok(dockItemSrc.includes("orbitBurst.stop();"));
    assert.ok(dockItemSrc.includes("Behavior on orbitMix"));
});
check("hover lens hugs the app glyph while beads orbit independently", () => {
    assert.ok(dockBodySrc.includes("var isAppIcon = !!target.item;"));
    assert.ok(dockBodySrc.includes("var focusSize = isAppIcon ? target.tile * 0.82 : 0;"));
    assert.ok(dockBodySrc.includes("var focusOffsetX = isAppIcon ? (target.width - focusSize) / 2 : 0;"));
    assert.ok(dockBodySrc.includes("var focusOffsetY = isAppIcon ? (target.height - focusSize) / 2 : 0;"));
    assert.ok(dockBodySrc.includes("root.lensX = p.x + focusOffsetX - inflate;"));
    assert.ok(dockBodySrc.includes("root.lensY = p.y + focusOffsetY - inflate;"));
    assert.ok(dockBodySrc.includes("root.lensW = isAppIcon ? focusSize + 2 * inflate : target.width + 2 * inflate;"));
    assert.ok(dockBodySrc.includes("root.lensH = isAppIcon ? focusSize + 2 * inflate : target.height + 2 * inflate;"));
    assert.ok(!dockBodySrc.includes("var pipRoom = hasPips ? 8 * root.s : 0;"));
    assert.ok(dockItemSrc.includes("root.windowActivated(pipHit.index)"));
});
check("window beads stay outside the rounded focus frame and inside the dock", () => {
    assert.ok(dockItemSrc.includes("readonly property real semiMajorAxis: 28.3 * root.s"));
    assert.ok(dockItemSrc.includes("readonly property real eccentricity: 0.01"));
    assert.ok(dockItemSrc.includes("x: -12 * root.s"));
    assert.ok(dockItemSrc.includes("width: root.width + 24 * root.s"));
    assert.ok(dockItemSrc.includes("width: pipHit.windowActive ? 4 * root.s : 3 * root.s"));
    assert.ok(dockItemSrc.includes("width: parent.width * 1.2"));
    assert.ok(dockItemSrc.includes("root.width + 4 * root.s : -4 * root.s"));
    assert.ok(dockItemSrc.includes("root.height / 2 + orbitalPosition.y - height / 2 + 12 * root.s"));

    const lensHalfSize = (44 * 0.82 + 8) / 2;
    const lensCornerRadius = 16;
    const lensCornerReach = Math.SQRT2 * (lensHalfSize - lensCornerRadius + lensCornerRadius / Math.SQRT2);
    const minOrbitRadius = 28.3 * (1 - 0.01);
    const maxOrbitRadius = 28.3 * (1 + 0.01);
    const activeHaloRadius = 4 * 1.2 / 2;
    const capsuleHalfWidth = 44 / 2 + 9;
    const staticRailCenterRadius = 26;
    assert.ok(minOrbitRadius - activeHaloRadius > lensCornerReach,
        "active bead halo must clear the rounded corners throughout its orbit");
    assert.ok(maxOrbitRadius + activeHaloRadius < capsuleHalfWidth,
        "active bead halo must remain inside the glass capsule");
    assert.ok(staticRailCenterRadius - activeHaloRadius > lensHalfSize,
        "active bead halo must clear the focus frame on the resting rail");
    assert.ok(dockItemSrc.includes("width: 10 * root.s"),
        "keep the larger invisible hit targets for easy clicking");
});

check("status controls use equal-height cells and reserve space for battery text", () => {
    assert.ok(dockButtonSrc.includes("property real tileHeight: 44 * s"));
    assert.ok(dockButtonSrc.includes("height: tileHeight"));
    assert.ok(dockButtonSrc.includes("property real faceVerticalOffset: 0"));
    assert.ok(dockButtonSrc.includes("anchors.verticalCenterOffset: root.faceVerticalOffset * root.s"));
    assert.ok(dockButtonSrc.includes("anchors.bottomMargin: 1 * root.s"));
    assert.ok(dockBodySrc.includes("faceVerticalOffset: -4"));
    assert.ok(dockBodySrc.includes("var inflate = (isAppIcon ? 4 : 0) * root.s;"));
    assert.ok(dockBodySrc.includes("target.height / 2 + faceOffsetY"));
    assert.ok(dockBodySrc.includes("id: cluster"));
    assert.ok(dockBodySrc.includes("spacing: root.gap"));
    assert.ok(dockBodySrc.includes("faceVerticalOffset * target.s"));
});

check("glass lens keeps one outline and no refraction streaks", () => {
    assert.ok(dockItemSrc.includes("Compact glass bead: tinted core, darkened lower edge, bright rim"));
    assert.ok(dockItemSrc.includes("Qt.lighter(Theme.onGlow, 1.65)"));
    assert.ok(dockItemSrc.includes("The glint is deliberately offset"));
    const match = dockBodySrc.match(/\/\/ The lens:[\s\S]*?Rectangle\s*\{([\s\S]*?)\n            \}/);
    assert.ok(match, "shared hover lens should exist");
    assert.ok(match[1].includes("GradientStop { position: 0; color: Qt.alpha(Theme.bright, 0.15) }"));
    assert.ok(match[1].includes("border.width: 1"));
    assert.ok(!match[1].includes("Refraction-inspired streaks"));
    assert.ok(!match[1].includes("anchors.top: parent.top"));
});

check("hover lens remains visible through its contraction before fading", () => {
    assert.ok(dockBodySrc.includes("property bool lensContracting: false"));
    assert.ok(dockBodySrc.includes("root.lensContracting = true;"));
    assert.ok(dockBodySrc.includes("id: lensContractionDelay"));
    assert.ok(dockBodySrc.includes("interval: Motion.glide"));
    assert.ok(dockBodySrc.includes("opacity: root.lensTarget || root.lensContracting ? 1 : 0"));
});

check("hover lens contracts into a small centered shape when pointer leaves", () => {
    assert.ok(dockBodySrc.includes("var centerX = root.lensX + root.lensW / 2;"));
    assert.ok(dockBodySrc.includes("var centerY = root.lensY + root.lensH / 2;"));
    assert.ok(dockBodySrc.includes("var collapsedSize = 8 * root.s;"));
    assert.ok(dockBodySrc.includes("root.lensW = collapsedSize;"));
    assert.ok(dockBodySrc.includes("root.lensH = collapsedSize;"));
    assert.ok(dockBodySrc.includes("radius: Math.min(16 * root.s, width / 2, height / 2)"));
    assert.ok(dockBodySrc.includes("Behavior on width"));
    assert.ok(dockBodySrc.includes("Behavior on height"));
});

console.log("nextWindow");
check("none running means launch", () => assert.strictEqual(D.nextWindow({ windows: [] }, ""), null));
check("no focused window picks the first visible one", () => {
    const item = { windows: [win("0x1", "f", "special:minimized"), win("0x2", "f")] };
    assert.strictEqual(D.nextWindow(item, "").address, "0x2");
});
check("only minimized windows picks the first", () => {
    const item = { windows: [win("0x1", "f", "special:minimized")] };
    assert.strictEqual(D.nextWindow(item, "").address, "0x1");
});
check("repeated clicks walk through the windows and wrap", () => {
    const item = { windows: [win("0x1", "f"), win("0x2", "f"), win("0x3", "f")] };
    assert.strictEqual(D.nextWindow(item, "0x1").address, "0x2");
    assert.strictEqual(D.nextWindow(item, "0x3").address, "0x1");
});
check("a focus elsewhere starts from the first window", () => {
    const item = { windows: [win("0x1", "f"), win("0x2", "f")] };
    assert.strictEqual(D.nextWindow(item, "0x99").address, "0x1");
});

console.log("windowAt");
check("pip index selects the matching window", () => {
    const item = { windows: [win("0x1", "f"), win("0x2", "f"), win("0x3", "f")] };
    assert.strictEqual(D.windowAt(item, 0).address, "0x1");
    assert.strictEqual(D.windowAt(item, 1).address, "0x2");
    assert.strictEqual(D.windowAt(item, 2).address, "0x3");
});
check("windowAt rejects missing, fractional and out-of-range indexes", () => {
    const item = { windows: [win("0x1", "f")] };
    assert.strictEqual(D.windowAt(item, -1), null);
    assert.strictEqual(D.windowAt(item, 1), null);
    assert.strictEqual(D.windowAt(item, 0.5), null);
    assert.strictEqual(D.windowAt(null, 0), null);
});

console.log("dock hover styling");
check("missing app icons receive a styled, readable monogram tile", () => {
    assert.ok(dockItemSrc.includes("Missing app artwork gets a deliberate monogram tile"));
    assert.ok(dockItemSrc.includes("width: parent.width * 0.84"));
    assert.ok(dockItemSrc.includes("color: Qt.alpha(Theme.onGlow, 0.18)"));
    assert.ok(dockItemSrc.includes("font.pixelSize: root.tile * 0.48"));
    assert.ok(dockItemSrc.includes("visible: !icon.visible"));
});
check("focused app backing has no nested border", () => {
    const match = dockItemSrc.match(/\/\/ Focused app:[\s\S]*?Rectangle\s*\{([\s\S]*?)\n    \}/);
    assert.ok(match, "focused app backing should exist");
    assert.ok(!/border\.(width|color)\s*:/.test(match[1]), "focused app backing must not draw an outline");
});
check("persistent active tint stays compact around the icon", () => {
    assert.ok(dockItemSrc.includes("anchors.centerIn: iconBox"));
    assert.ok(dockItemSrc.includes("width: iconBox.width + 14 * root.s"));
    assert.ok(dockItemSrc.includes("height: width"));
});
check("shared hover lens keeps the single moving outline", () => {
    const match = dockBodySrc.match(/\/\/ The lens:[\s\S]*?Rectangle\s*\{([\s\S]*?)\n            \}/);
    assert.ok(match, "shared hover lens should exist");
    assert.ok(/border\.width\s*:\s*1/.test(match[1]), "shared lens should retain its outline");
    assert.ok(/Behavior on x/.test(match[1]), "shared outline should move with the cursor");
});

console.log("focus dispatcher");
check("Lua-mode focus uses the Lua dispatcher expression", () => {
    assert.ok(dockSingletonSrc.includes("if (Hyprland.usingLua)"));
    assert.ok(dockSingletonSrc.includes('hl.dsp.focus({ window = "'));
});
check("Lua-mode minimized-window restore moves the selected window", () => {
    assert.ok(dockSingletonSrc.includes('hl.dsp.window.move({ workspace = " + workspace + ", follow = false })'));
});
check("legacy Hyprland mode retains standard dispatcher syntax", () => {
    assert.ok(dockSingletonSrc.includes('Hyprland.dispatch("focuswindow " + selector)'));
    assert.ok(dockSingletonSrc.includes('Hyprland.dispatch("movetoworkspace "'));
});

console.log("pins");
check("togglePin adds at the end", () => same(D.togglePin(["a"], "b"), ["a", "b"]));
check("togglePin removes an existing pin, ignoring case and .desktop", () => {
    same(D.togglePin(["a", "Firefox"], "firefox.desktop"), ["a"]);
});
check("togglePin leaves the caller's array alone", () => {
    const p = ["a"];
    D.togglePin(p, "b");
    same(p, ["a"]);
});
check("movePin reorders", () => same(D.movePin(["a", "b", "c"], 2, 0), ["c", "a", "b"]));
check("movePin ignores out-of-range and no-op moves", () => {
    same(D.movePin(["a", "b"], 5, 0), ["a", "b"]);
    same(D.movePin(["a", "b"], 1, 1), ["a", "b"]);
});

if (failed) { console.log("\n" + failed + " failed"); process.exit(1); }
console.log("\nall ok");
