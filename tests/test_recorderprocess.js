#!/usr/bin/env node
"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const helperPath = path.join(__dirname, "..", "configs", "quickshell", "pill", "lib", "recorderprocess.js");
const helperSource = fs.readFileSync(helperPath, "utf8").replace(/^\.pragma library\s*/, "");
const context = {};
vm.runInNewContext(helperSource, context, { filename: helperPath });

assert.deepEqual(Array.from(context.interruptCommand(4321)), ["kill", "-INT", "4321"]);
for (const pid of [undefined, null, "", 0, 1, -1, 1.5, "not-a-pid"]) {
    assert.deepEqual(Array.from(context.interruptCommand(pid)), [], `unsafe PID is rejected: ${String(pid)}`);
}

assert.equal(context.canStart(false, false, false, "DP-1"), true);
assert.equal(context.canStart(true, false, false, "DP-1"), false, "do not start over an active recording");
assert.equal(context.canStart(false, true, false, "DP-1"), false, "do not start while recorder process is running");
assert.equal(context.canStart(false, false, true, "DP-1"), false, "do not overlap directory preparation");
assert.equal(context.canStart(false, false, false, "  "), false, "do not start without a resolved capture target");
assert.equal(context.directoryReady(0), true);
for (const code of [1, 2, 126, 127, -1, undefined, null]) {
    assert.equal(context.directoryReady(code), false, `nonzero/unknown mkdir exit is failure: ${String(code)}`);
}

const screenRecPath = path.join(__dirname, "..", "configs", "quickshell", "pill", "Singletons", "ScreenRec.qml");
const screenRec = fs.readFileSync(screenRecPath, "utf8");
assert.match(screenRec, /RecorderProcess\.interruptCommand\(recProc\.processId\)/);
assert.doesNotMatch(screenRec, /pkill[^\n]*gpu-screen-recorder/);
assert.match(screenRec, /RecorderProcess\.canStart\(recording, recProc\.running, mkdirProc\.running, captureToken\)/);
assert.match(screenRec, /if \(!RecorderProcess\.directoryReady\(exitCode\)\)/);
assert.match(screenRec, /readonly property bool busy: recording \|\| recProc\.running \|\| mkdirProc\.running \|\| picking \|\| counting/);

const recorderUiPath = path.join(__dirname, "..", "configs", "quickshell", "pill", "Recorder.qml");
const recorderUi = fs.readFileSync(recorderUiPath, "utf8");
assert.match(recorderUi, /ScreenRec\.canStop \? "Stop recording" : "External recording"/);
console.log("  ok   screen recorder stop targets one validated PID, never every matching process");
