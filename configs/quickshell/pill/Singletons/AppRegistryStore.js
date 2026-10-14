.pragma library

// Keep parsing independent of AppRegistry so the error cases can be tested
// without starting the compositor. Callers must never treat a parse failure as
// an empty registry: an existing file that cannot be parsed is user data.
function parse(raw) {
    if (typeof raw !== "string")
        throw new Error("applications.json did not return text");
    if (raw.trim().length === 0)
        throw new Error("applications.json is empty");

    var records = JSON.parse(raw);
    if (!Array.isArray(records))
        throw new Error("applications.json must contain a JSON array");

    for (var i = 0; i < records.length; i++) {
        var record = records[i];
        if (record === null || typeof record !== "object" || Array.isArray(record))
            throw new Error("applications.json entry " + i + " must be an object");
    }
    return records;
}
