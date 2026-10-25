.pragma library

/*
 * Runner-aware launch target contract shared by the UI model and process
 * launcher. A Steam AppID is a complete launch target; Wine/UMU require an
 * executable, while native records can resolve through a desktop entry.
 */

function text(value) {
    return String(value === undefined || value === null ? "" : value).trim();
}

function lower(value) {
    return text(value).toLowerCase();
}

function hasSteamAppId(value) {
    return /^[0-9]+$/.test(text(value));
}

function targetStatus(app, runner, runtimeReady) {
    if (!app) {
        return {
            valid: false,
            runner: "",
            requiresExecutable: true,
            reason: "No application record was supplied."
        };
    }

    var selected = lower(runner || app.runner || "auto");
    var executable = text(app.executable);
    var desktopEntryId = text(app.desktopEntryId);
    var steamAppId = text(app.steamAppId);

    if (selected === "steam") {
        if (hasSteamAppId(steamAppId))
            return { valid: true, runner: selected, requiresExecutable: false, reason: "" };
        return {
            valid: false,
            runner: selected,
            requiresExecutable: false,
            reason: "Steam needs this game's numeric App ID. Set it in the game editor or choose another runner."
        };
    }

    if (selected === "native") {
        if (executable.length > 0 || desktopEntryId.length > 0)
            return { valid: true, runner: selected, requiresExecutable: false, reason: "" };
        return {
            valid: false,
            runner: selected,
            requiresExecutable: true,
            reason: "Choose the executable or desktop entry command before launching this application."
        };
    }

    if (selected === "wine" || selected === "wine-staging" || selected === "umu") {
        if (executable.length > 0)
            return { valid: true, runner: selected, requiresExecutable: false, reason: "" };
        return {
            valid: false,
            runner: selected,
            requiresExecutable: true,
            reason: "Choose the game's launch executable before launching it."
        };
    }

    if (selected === "auto") {
        if (executable.length > 0 || desktopEntryId.length > 0)
            return { valid: true, runner: selected, requiresExecutable: false, reason: "" };
        if (hasSteamAppId(steamAppId) && runtimeReady === false) {
            return {
                valid: true,
                runner: selected,
                requiresExecutable: false,
                pendingRuntime: true,
                reason: "Runtime detection has not completed."
            };
        }
        return {
            valid: false,
            runner: selected,
            requiresExecutable: true,
            reason: "Choose a launch executable or wait for automatic runner detection."
        };
    }

    return {
        valid: false,
        runner: selected,
        requiresExecutable: true,
        reason: "Unsupported launch runner: " + selected
    };
}
