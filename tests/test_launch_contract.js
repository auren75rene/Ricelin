"use strict";

const assert = require("assert");
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const sourcePath = path.join(__dirname, "..", "configs", "quickshell", "pill", "lib", "launchcontract.js");
const source = fs.readFileSync(sourcePath, "utf8").replace(/^\.pragma library\s*/, "");
const context = {};
vm.createContext(context);
vm.runInContext(source, context, { filename: sourcePath });

let passed = 0;
function check(name, fn) {
    fn();
    passed++;
    console.log("ok " + name);
}

check("Steam AppID is sufficient without a local executable", () => {
    const status = context.targetStatus({ runner: "steam", steamAppId: "698780", executable: "" }, "steam", true);
    assert.strictEqual(status.valid, true);
    assert.strictEqual(status.requiresExecutable, false);
});

check("Steam requires a numeric AppID and reports the right remedy", () => {
    const status = context.targetStatus({ runner: "steam", steamAppId: "", executable: "" }, "steam", true);
    assert.strictEqual(status.valid, false);
    assert.strictEqual(status.requiresExecutable, false);
    assert.match(status.reason, /numeric App ID/i);
});

check("Wine requires an executable", () => {
    const status = context.targetStatus({ runner: "wine", executable: "" }, "wine", true);
    assert.strictEqual(status.valid, false);
    assert.strictEqual(status.requiresExecutable, true);
});

check("Wine accepts a configured executable", () => {
    assert.strictEqual(context.targetStatus({ runner: "wine", executable: "/games/game.exe" }, "wine", true).valid, true);
});

check("native launch accepts a desktop-entry identity", () => {
    assert.strictEqual(context.targetStatus({ runner: "native", executable: "", desktopEntryId: "game.desktop" }, "native", true).valid, true);
});

check("native launch without either target needs configuration", () => {
    const status = context.targetStatus({ runner: "native", executable: "", desktopEntryId: "" }, "native", true);
    assert.strictEqual(status.valid, false);
    assert.strictEqual(status.requiresExecutable, true);
});

check("Auto defers AppID-only validation while runtime detection is pending", () => {
    const status = context.targetStatus({ runner: "auto", steamAppId: "698780", executable: "" }, "auto", false);
    assert.strictEqual(status.valid, true);
    assert.strictEqual(status.pendingRuntime, true);
});

check("Auto does not accept an AppID alone once detection has completed", () => {
    assert.strictEqual(context.targetStatus({ runner: "auto", steamAppId: "698780", executable: "" }, "auto", true).valid, false);
});

check("Auto accepts a configured target during startup", () => {
    assert.strictEqual(context.targetStatus({ runner: "auto", executable: "/games/game.exe" }, "auto", false).valid, true);
});

check("missing records are rejected", () => {
    assert.strictEqual(context.targetStatus(null, "steam", true).valid, false);
});

console.log(passed + " launch-contract tests passed");
