.pragma library

function steamAppIdFromExec(execString) {
    var match = String(execString || "").match(/steam\s+steam:\/\/rungameid\/([0-9]+)/i)
    return match ? match[1] : ""
}

function findEntry(entries, app) {
    if (!app || app.runner !== "native")
        return null

    var list = entries || []
    var wantedId = String(app.desktopEntryId || "")
    if (wantedId.length > 0) {
        for (var i = 0; i < list.length; ++i) {
            var entry = list[i]
            if (entry && !entry.noDisplay && String(entry.id || "") === wantedId)
                return entry
        }
    }

    // Backward compatibility for records created before desktopEntryId existed.
    var oldId = String(app.id || "")
    if (oldId.length > 0) {
        for (var j = 0; j < list.length; ++j) {
            var byId = list[j]
            if (byId && !byId.noDisplay && String(byId.id || "") === oldId)
                return byId
        }
    }

    var wantedName = String(app.name || "").toLowerCase()
    if (wantedName.length > 0) {
        for (var k = 0; k < list.length; ++k) {
            var byName = list[k]
            if (byName && !byName.noDisplay && String(byName.name || "").toLowerCase() === wantedName)
                return byName
        }
    }
    return null
}

function nativeCommand(app, entry) {
    var executable = String(app && app.executable || "")
    var args = Array.isArray(app && app.args) ? app.args.map(String) : []
    var entryCommand = entry && Array.isArray(entry.command) ? entry.command.map(String) : []

    // Legacy records sometimes persisted raw desktop-entry Exec text as their
    // executable. In that case use Qt's already-parsed argv, never pass Exec
    // through a shell. Otherwise the registry's executable/args are authoritative
    // so edits made in AppEditor are not silently discarded.
    if (entryCommand.length > 0 &&
        (executable.length === 0 || executable === String(entry.execString || ""))) {
        return entryCommand
    }

    return [executable].concat(args)
}

function workingDirectoryFor(app, entry) {
    var explicit = String(app && app.workingDirectory || "")
    if (explicit.length > 0)
        return explicit

    var fromEntry = String(entry && entry.workingDirectory || "")
    if (fromEntry.length > 0)
        return fromEntry

    var executable = String(app && app.executable || "")
    var i = executable.lastIndexOf("/")
    return i > 0 ? executable.slice(0, i) : executable
}

function fromEntry(entry, category) {
    var command = []
    if (entry && entry.command && entry.command.length > 0) {
        for (var i = 0; i < entry.command.length; ++i)
            command.push(String(entry.command[i]))
    }

    var steamAppId = steamAppIdFromExec(entry && entry.execString)
    var isSteam = steamAppId.length > 0

    return {
        source: isSteam ? "STEAM" : "DESKTOP",
        discoverySource: "DESKTOP",
        name: String(entry && entry.name || ""),
        executable: isSteam ? "" : (command.length > 0 ? command[0] : ""),
        args: isSteam ? [] : command.slice(1),
        desktopEntryId: String(entry && entry.id || ""),
        workingDirectory: String(entry && entry.workingDirectory || ""),
        prefix: "",
        category: category,
        runner: isSteam ? "steam" : "native",
        steamAppId: steamAppId
    }
}
