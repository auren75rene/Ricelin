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

const entries = [
    { id: "hidden.desktop", name: "Editor", noDisplay: true, command: ["/hidden"] },
    { id: "org.example.Editor.desktop", name: "Renamed Editor", command: ["/opt/Editor", "--profile", "space path"], workingDirectory: "/opt/work", execString: '"/opt/Editor" --profile "space path"' },
    { id: "fallback.desktop", name: "Editor", command: ["/opt/fallback"] }
];
const selected = context.findEntry(entries, {
    runner: "native",
    desktopEntryId: "org.example.Editor.desktop",
    name: "Editor"
});
assert.equal(selected.id, "org.example.Editor.desktop", "stable desktop entry ID wins over a duplicate display name");
console.log("  ok   native desktop entry resolution prefers stable ID and ignores NoDisplay");

const savedEntry = {
    command: ["editor", "--open", "--profile", "/tmp/profile with spaces"],
    execString: 'editor --open "%U"'
};
assert.deepEqual(Array.from(context.nativeCommand(native, savedEntry)), ["editor", "--open", "--profile", "/tmp/profile with spaces"]);
console.log("  ok   imported native app uses stored parsed argv with spaces");

const edited = {
    executable: "/custom/editor",
    args: ["--profile", "a path with spaces"],
    workingDirectory: "",
    desktopEntryId: "org.example.Editor.desktop"
};
assert.deepEqual(Array.from(context.nativeCommand(edited, entries[1])), ["/custom/editor", "--profile", "a path with spaces"]);
assert.equal(context.workingDirectoryFor(edited, entries[1]), "/opt/work");
assert.equal(context.workingDirectoryFor({ executable: "/custom/bin/editor", workingDirectory: "/explicit/work" }, entries[1]), "/explicit/work");
console.log("  ok   user-edited executable/arguments and working directory are respected");

const legacy = { executable: entries[1].execString, args: [], workingDirectory: "" };
assert.deepEqual(Array.from(context.nativeCommand(legacy, entries[1])), ["/opt/Editor", "--profile", "space path"]);
console.log("  ok   legacy raw Exec records use parsed argv instead of shell text");
