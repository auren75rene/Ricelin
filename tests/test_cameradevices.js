#!/usr/bin/env node
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");
const path = require("node:path");

const sourcePath = path.join(__dirname, "..", "configs", "quickshell", "pill", "lib", "cameradevices.js");
const source = fs.readFileSync(sourcePath, "utf8").replace(/^\.pragma library\s*/, "");
const context = {};
vm.runInNewContext(source, context, { filename: sourcePath });

assert.equal(context.v4l2Path("/dev/video0"), "/dev/video0");
assert.equal(context.v4l2Path("v4l2:/dev/video12"), "/dev/video12");
assert.equal(context.v4l2Path("/dev/video3?camera=selected"), "/dev/video3");
assert.equal(context.v4l2Path("platform:camera-front"), "");
assert.equal(context.v4l2Path(""), "");
assert.equal(context.v4l2Path("/dev/video0-extra"), "", "partial device IDs are not accepted");
console.log("  ok   V4L2 path resolver only returns concrete device nodes");

assert.equal(context.shouldKeepScreenCamera(true, true), true);
assert.equal(context.shouldKeepScreenCamera(true, false), false);
assert.equal(context.shouldKeepScreenCamera(false, true), false);
assert.equal(context.shouldKeepScreenCamera(false, false), false);
console.log("  ok   screen-camera lifecycle retains camera only during screen recording");

assert.equal(context.shouldDeferCameraStop(false, false, false), false);
assert.equal(context.shouldDeferCameraStop(true, false, false), true);
assert.equal(context.shouldDeferCameraStop(false, true, false), true);
assert.equal(context.shouldDeferCameraStop(false, false, true), true);
console.log("  ok   camera shutdown waits for active or starting capture work");

assert.equal(context.shouldFinishPendingCameraStop(true, false, false, false), true);
assert.equal(context.shouldFinishPendingCameraStop(false, false, false, false), false);
assert.equal(context.shouldFinishPendingCameraStop(true, true, false, false), false);
assert.equal(context.shouldFinishPendingCameraStop(true, false, true, false), false);
assert.equal(context.shouldFinishPendingCameraStop(true, false, false, true), false);
console.log("  ok   deferred camera shutdown completes only after capture finalization");

const cameraQmlPath = path.join(__dirname, "..", "configs", "quickshell", "pill", "Singletons", "CameraRec.qml");
const cameraQml = fs.readFileSync(cameraQmlPath, "utf8");
assert.match(cameraQml, /CameraDevices\.shouldDeferCameraStop\(videoRecording, capturingPhoto, startingVideo\)/);
assert.match(cameraQml, /CameraDevices\.shouldFinishPendingCameraStop\(/);
assert.match(cameraQml, /if \(root\.cameraStopPending \|\| !root\.cameraActive\)/);
assert.match(cameraQml, /startingVideo = true/);
console.log("  ok   CameraRec defers shutdown and cancels not-yet-started video when closing");
