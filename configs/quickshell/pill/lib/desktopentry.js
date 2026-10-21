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

function isWindowsTarget(value) {
    var text = String(value || "").trim();
    return /\.(exe|lnk|msi|bat|cmd)$/i.test(text) || /^[a-z]:[\\/]/i.test(text);
}

function wineLaunchDetails(entry, command) {
    var prefix = "";
    var runner = "";
    var runnerAt = -1;
    var environment = ({});

    // Inspect Quickshell's parsed argv. Never pass desktop Exec text through a shell.
    for (var i = 0; i < command.length; ++i) {
        var token = String(command[i] || "");
        var assignment = token.match(/^([A-Za-z_][A-Za-z0-9_]*)=(.*)$/);
        if (assignment && assignment[1].toUpperCase() === "WINEPREFIX")
            prefix = assignment[2].replace(/^["']|["']$/g, "");

        var binary = token.replace(/\\/g, "/").split("/").pop().toLowerCase();
        if (binary === "umu-run") {
            runner = "umu";
            runnerAt = i;
            break;
        }
        if (binary === "wine-staging" || binary === "wine-staging64") {
            runner = "wine-staging";
            runnerAt = i;
            break;
        }
        if (binary === "wine" || binary === "wine64") {
            runner = "wine";
            runnerAt = i;
            break;
        }
    }

    // Some providers expose environment assignments only in Exec text.
    // This extracts metadata; the command itself still comes from parsed argv.
    if (!prefix) {
        var rawPrefix = String(entry && entry.execString || "")
            .match(/WINEPREFIX=(?:"([^"]+)"|'([^']+)'|([^\s"]+))/i);
        if (rawPrefix)
            prefix = rawPrefix[1] || rawPrefix[2] || rawPrefix[3] || "";
    }
    if (!prefix || runnerAt < 0)
        return null;

    for (var e = 0; e < runnerAt; ++e) {
        var envMatch = String(command[e] || "").match(/^([A-Za-z_][A-Za-z0-9_]*)=(.*)$/);
        if (!envMatch || envMatch[1].toUpperCase() === "WINEPREFIX")
            continue;
        environment[envMatch[1]] = envMatch[2];
    }

    var targetAt = -1;
    for (var j = runnerAt + 1; j < command.length; ++j) {
        if (isWindowsTarget(command[j])) {
            targetAt = j;
            break;
        }
    }

    // File-association handlers such as wine start /ProgIDOpen are not app targets.
    if (targetAt < 0)
        return null;

    var args = [];
    for (var a = targetAt + 1; a < command.length; ++a)
        args.push(String(command[a]));

    return {
        runner: runner,
        executable: String(command[targetAt]),
        args: args,
        prefix: prefix,
        env: environment,
        protonBuild: environment.PROTONPATH || ""
    };
}

function fromEntry(entry, category) {
    var command = [];
    if (entry && entry.command && entry.command.length > 0) {
        for (var i = 0; i < entry.command.length; ++i)
            command.push(String(entry.command[i]));
    }

    var steamAppId = steamAppIdFromExec(entry && entry.execString);
    var isSteam = steamAppId.length > 0;
    var wineLaunch = isSteam ? null : wineLaunchDetails(entry, command);

    return {
        source: isSteam ? "STEAM" : (wineLaunch ? "WINE_DESKTOP" : "DESKTOP"),
        discoverySource: "DESKTOP",
        name: String(entry && entry.name || ""),
        executable: isSteam ? "" : (wineLaunch ? wineLaunch.executable : (command.length > 0 ? command[0] : "")),
        args: isSteam ? [] : (wineLaunch ? wineLaunch.args : command.slice(1)),
        desktopEntryId: String(entry && entry.id || ""),
        workingDirectory: String(entry && entry.workingDirectory || ""),
        prefix: wineLaunch ? wineLaunch.prefix : "",
        env: wineLaunch ? wineLaunch.env : {},
        protonBuild: wineLaunch ? wineLaunch.protonBuild : "",
        category: category,
        runner: isSteam ? "steam" : (wineLaunch ? wineLaunch.runner : "native"),
        steamAppId: steamAppId
    };
}
