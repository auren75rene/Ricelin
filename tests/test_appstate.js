#!/usr/bin/env node
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");
const assert = require("assert");
const file = path.join(__dirname, "..", "configs", "quickshell", "pill", "lib", "appstate.js");
const src = fs.readFileSync(file, "utf8").split("\n").filter(line => !line.startsWith(".pragma")).join("\n");
const ctx = {};
vm.createContext(ctx);
vm.runInContext(src, ctx);
const S = ctx;
const base = { exists: true, targetValid: true, windowCount: 0 };
const checks = [
  ["unknown entries are idle", () => assert.strictEqual(S.deriveState({ exists: false }), "idle")],
  ["active window state wins over launch process", () => assert.strictEqual(S.deriveState({ ...base, windowCount: 1, launching: true }), "running")],
  ["stop request has highest priority", () => assert.strictEqual(S.deriveState({ ...base, stopping: true, windowCount: 1 }), "stopping")],
  ["failure is shown before a stale window match", () => assert.strictEqual(S.deriveState({ ...base, failed: true, windowCount: 1 }), "failed")],
  ["missing install precedes setup", () => assert.strictEqual(S.deriveState({ ...base, folderMissing: true, needsSetup: true }), "missing")],
  ["setup status precedes preparation", () => assert.strictEqual(S.deriveState({ ...base, needsSetup: true, pending: true }), "setup")],
  ["prefix work is preparing", () => assert.strictEqual(S.deriveState({ ...base, pending: true }), "preparing")],
  ["a request waiting for its window is launching", () => assert.strictEqual(S.deriveState({ ...base, launching: true }), "launching")],
  ["a workspace queue is waiting", () => assert.strictEqual(S.deriveState({ ...base, waiting: true }), "waiting")],
  ["no outstanding work is idle", () => assert.strictEqual(S.deriveState(base), "idle")],
  ["an app is active from a managed process", () => assert.ok(S.isActive({ processRunning: true, windowCount: 0 }))],
  ["a Steam game is active from its matching window after CLI exits", () => assert.ok(S.isActive({ processRunning: false, windowCount: 1 }))],
  ["a queued request is not itself running", () => assert.ok(!S.isActive({ processRunning: false, windowCount: 0, launching: true }))],
];
let errors = 0;
for (const [name, test] of checks) {
  try { test(); console.log("  ok   " + name); }
  catch (error) { errors++; console.error("  FAIL " + name + "\n       " + error.message); }
}
if (errors) process.exit(1);
console.log("\nall " + checks.length + " app-state checks passed");
