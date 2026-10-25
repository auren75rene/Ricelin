// Self-check for configs/quickshell/pill/lib/blades.js. The file is a QML
// `.pragma library`, so the pragma line is stripped and the rest runs in a vm.
// Run: node tests/test_blades.js
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");
const assert = require("assert");

const file = path.join(__dirname, "..", "configs", "quickshell", "pill", "lib", "blades.js");
const src = fs.readFileSync(file, "utf8").split("\n").filter(line => !line.startsWith(".pragma")).join("\n");
const ctx = {};
vm.createContext(ctx);
vm.runInContext(src, ctx);
const B = ctx;

let failed = 0;
function check(name, fn) {
    try { fn(); console.log("  ok   " + name); }
    catch (e) { failed++; console.log("  FAIL " + name + "\n         " + e.message); }
}
const rec = (o) => Object.assign({ id: "x", name: "X", category: "game", runner: "wine", favorite: false, lastLaunched: 0, createdAt: 0 }, o);
const names = (list) => list.map((a) => a.name).join(",");

console.log("eligible");
check("a game is in by default", () => assert.ok(B.eligible(rec({}))));
check("a utility does not appear by default even with Wine", () => assert.ok(!B.eligible(rec({ category: "utility", runner: "wine" }))));
check("Wine-family runners do not override category", () => {
    for (const r of ["wine", "wine-staging", "umu", "steam"])
        assert.ok(!B.eligible(rec({ category: "utility", runner: r })), r);
});
check("a native utility is out", () => assert.ok(!B.eligible(rec({ category: "utility", runner: "native" }))));
check("a native game is in", () => assert.ok(B.eligible(rec({ category: "game", runner: "native" }))));
check("hide wins over everything", () => assert.ok(!B.eligible(rec({ blade: "hide", favorite: true }))));
check("pin brings in a native utility", () => assert.ok(B.eligible(rec({ category: "utility", runner: "native", blade: "pin" }))));
check("unknown blade values mean auto", () => assert.ok(B.eligible(rec({ blade: "banana" }))));
check("a record without an id is never listed", () => assert.ok(!B.eligible(rec({ id: "" }))));
check("null and undefined are tolerated", () => { assert.ok(!B.eligible(null)); assert.ok(!B.eligible(undefined)); });
check("case does not matter", () => assert.ok(B.eligible(rec({ category: "Game", runner: "WINE" }))));

console.log("order");
check("pin/favourite priority is stable and recent launches do not reorder blades", () => {
    const apps = [
        rec({ id: "a", name: "Alpha", bladeOrder: 0, lastLaunched: 999 }),
        rec({ id: "b", name: "Bravo", bladeOrder: 1, lastLaunched: 10 }),
        rec({ id: "c", name: "Charlie", favorite: true, bladeOrder: 2 }),
        rec({ id: "d", name: "Delta", category: "utility", runner: "native", blade: "pin", bladeOrder: 3 }),
        rec({ id: "e", name: "Echo", bladeOrder: 4, lastLaunched: 500 }),
    ];
    assert.strictEqual(names(B.select(apps, 0)), "Delta,Charlie,Alpha,Bravo,Echo");
});
check("name order is case-insensitive", () => {
    const apps = [rec({ id: "1", name: "zeta" }), rec({ id: "2", name: "Alpha" })];
    assert.strictEqual(names(B.select(apps, 0)), "Alpha,zeta");
});

console.log("cap");
check("max keeps the first N in blade order", () => {
    const apps = ["A", "B", "C", "D"].map((n, i) => rec({ id: n, name: n, bladeOrder: i, lastLaunched: 3 - i }));
    assert.strictEqual(names(B.select(apps, 2)), "A,B");
});
check("max 0 means no cap", () => {
    const apps = ["A", "B", "C"].map((n) => rec({ id: n, name: n }));
    assert.strictEqual(B.select(apps, 0).length, 3);
});
check("select does not reorder the caller's array", () => {
    const apps = [rec({ id: "z", name: "Z" }), rec({ id: "a", name: "A" })];
    B.select(apps, 0);
    assert.strictEqual(apps[0].name, "Z");
});
check("empty and missing lists give an empty list", () => {
    assert.strictEqual(B.select([], 6).length, 0);
    assert.strictEqual(B.select(null, 6).length, 0);
});

console.log("window matching");
check("desktop-entry ID matches a short WM class", () => {
    assert.ok(B.matchesWindow(
        rec({ id: "firefox", name: "Firefox", runner: "native", desktopEntryId: "org.mozilla.firefox" }),
        { cls: "firefox", title: "Mozilla Firefox" },
        { id: "org.mozilla.firefox.desktop", name: "Firefox", startupClass: "org.mozilla.firefox" }
    ));
});
check("Wine executable basename matches a Windows WM class", () => {
    assert.ok(B.matchesWindow(
        rec({ id: "cyberpunk-2077", name: "Cyberpunk 2077", executable: "/games/Cyberpunk2077.exe" }),
        { cls: "Cyberpunk2077.exe", title: "Cyberpunk 2077" },
        null
    ));
});
check("an exact title can identify a window with a generic class", () => {
    assert.ok(B.matchesWindow(
        rec({ id: "game", name: "Cyberpunk 2077" }),
        { cls: "wine", title: "Cyberpunk 2077" },
        null
    ));
});
check("similar but non-identical titles are not fuzzy-matched", () => {
    assert.ok(!B.matchesWindow(
        rec({ id: "doom", name: "Doom" }),
        { cls: "wine", title: "Doom Eternal" },
        null
    ));
});
check("Steam AppID window class matches without a local executable", () => {
    assert.ok(B.matchesWindow(
        rec({ id: "ddlc", name: "Doki Doki Literature Club", category: "game", runner: "steam", steamAppId: "698780", executable: "" }),
        { cls: "steam_app_698780", title: "Doki Doki Literature Club" },
        null
    ));
});
check("missing app/window records do not match", () => {
    assert.ok(!B.matchesWindow(null, { cls: "firefox" }, null));
    assert.ok(!B.matchesWindow(rec({}), null, null));
});


console.log("screen-fitted ring geometry");
check("one ring uses the requested blade length", () => {
    const fit = B.fitLayout(6, 6, 250, 929, 255, 16, 64);
    assert.strictEqual(fit.ringCount, 1);
    assert.strictEqual(fit.bladeLength, 255);
    assert.strictEqual(fit.outerRadius, 505);
    assert.ok(!fit.overflows);
});
check("two and three rings remain separated and within the screen radius", () => {
    for (const count of [7, 12, 13, 18]) {
        const fit = B.fitLayout(count, 6, 250, 929, 255, 16, 64);
        assert.ok(fit.outerRadius <= 929 + 0.001, count + " overflows");
        assert.ok(fit.ringStep >= fit.bladeLength + fit.ringGap - 1e-9);
        assert.strictEqual(fit.placements.length, count);
    }
});
check("larger layouts shorten blades instead of overlapping radial bands", () => {
    for (const count of [24, 30, 36, 42, 48]) {
        const fit = B.fitLayout(count, 6, 250, 929, 255, 16, 64);
        assert.ok(fit.bladeLength < 255, count + " should fit by shortening cards");
        assert.ok(fit.outerRadius <= 929 + 0.001, count + " overflows");
    }
});
check("an extreme game count reports geometry overflow instead of claiming it fits", () => {
    const fit = B.fitLayout(54, 6, 250, 929, 255, 16, 64);
    assert.ok(fit.overflows);
});

console.log("window activation order");
const windows = [
    { address: "0x01", workspace: "1" },
    { address: "0x02", workspace: "special:minimized" },
    { address: "0x03", workspace: "2" },
];
check("clicking an active app cycles to its next window", () => {
    assert.strictEqual(B.nextWindow(windows, "0x01"), windows[1]);
});
check("an app on another workspace selects a visible window first", () => {
    assert.strictEqual(B.nextWindow(windows, "0x99"), windows[0]);
});
check("all-minimized apps still select a window to restore", () => {
    const minimized = [{ address: "0x11", workspace: "special:minimized" }];
    assert.strictEqual(B.nextWindow(minimized, ""), minimized[0]);
});
check("an empty window list selects nothing", () => {
    assert.strictEqual(B.nextWindow([], ""), null);
});

if (failed) { console.log("\n" + failed + " failed"); process.exit(1); }
console.log("\nall ok");
