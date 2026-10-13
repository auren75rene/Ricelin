.pragma library

function steamAppIdFromExec(execString) {
    var match = String(execString || "").match(/steam\s+steam:\/\/rungameid\/([0-9]+)/i)
    return match ? match[1] : ""
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
