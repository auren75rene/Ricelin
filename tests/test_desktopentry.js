#!/usr/bin/env node
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");
const path = require("node:path");

const sourcePath = path.join(__dirname, "..", "configs", "quickshell", "pill", "lib", "desktopentry.js");
const source = fs.readFileSync(sourcePath, "utf8").replace(/^\.pragma library\s*/, "");
const context = {};
vm.runInNewContext(source, context, { filename: sourcePath });

const native = context.fromEntry({
    id: "org.example.Editor.desktop",
    name: "Editor",
    execString: 'editor --open "%U"',
    command: ["editor", "--open", "--profile", "/tmp/profile with spaces"],
    workingDirectory: "/tmp/work path"
}, "development");
assert.equal(native.runner, "native");
assert.equal(native.executable, "editor");
assert.deepEqual(Array.from(native.args), ["--open", "--profile", "/tmp/profile with spaces"]);
assert.equal(native.desktopEntryId, "org.example.Editor.desktop");
assert.equal(native.workingDirectory, "/tmp/work path");
assert.notEqual(native.executable, native.execString);
console.log("  ok   native desktop entry uses parsed argv, ID and working directory");

const steam = context.fromEntry({
    id: "steam-620.desktop",
    name: "Portal",
    execString: "steam steam://rungameid/620",
    command: ["steam", "steam://rungameid/620"]
}, "game");
assert.equal(steam.runner, "steam");
assert.equal(steam.steamAppId, "620");
assert.equal(steam.executable, "");
console.log("  ok   Steam desktop entry retains its app ID");

const empty = context.fromEntry({ id: "empty.desktop", name: "Empty", execString: "", command: [] }, "utility");
assert.equal(empty.executable, "");
assert.deepEqual(Array.from(empty.args), []);
console.log("  ok   missing command never falls back to raw Exec text");
