#!/usr/bin/env node
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");
const path = require("node:path");

const sourcePath = path.join(__dirname, "..", "configs", "quickshell", "pill", "Singletons", "AppRegistryStore.js");
const source = fs.readFileSync(sourcePath, "utf8").replace(/^\.pragma library\s*/, "");
const context = {};
vm.runInNewContext(source, context, { filename: sourcePath });

function rejects(raw, pattern, name) {
    assert.throws(() => context.parse(raw), pattern, name);
    console.log("  ok   " + name);
}
function accepts(raw, expectedLength, name) {
    const records = context.parse(raw);
    assert.equal(records.length, expectedLength, name);
    console.log("  ok   " + name);
}

accepts("[]", 0, "valid empty array is valid data");
accepts('[{"id":"undertale","name":"Undertale"}]', 1, "valid registry records parse");
rejects("", /empty/, "empty existing file is rejected");
rejects("   \n\t", /empty/, "whitespace-only file is rejected");
rejects("[{\"id\":", /JSON|Unexpected|end/i, "truncated JSON is rejected");
rejects('{"id":"one"}', /JSON array/, "non-array JSON root is rejected");
rejects('[null]', /must be an object/, "null record is rejected");
rejects('[1]', /must be an object/, "primitive record is rejected");
rejects('[[{"id":"nested"}]]', /must be an object/, "array record is rejected");

console.log("\nall app registry parser tests passed");
