.pragma library

/**
 * Return the signal command for one known child process. Reject invalid PIDs
 * rather than letting a malformed value become a process-group signal.
 */
function interruptCommand(pid) {
    var value = Number(pid)
    if (!isFinite(value) || Math.floor(value) !== value || value <= 1)
        return []
    return ["kill", "-INT", String(value)]
}

/** Avoid launching twice while the output directory or recorder is starting. */
function canStart(recording, processRunning, directoryPreparing, captureToken) {
    return !recording
        && !processRunning
        && !directoryPreparing
        && String(captureToken || "").trim().length > 0
}

/** A failed mkdir must never be treated as a ready recording destination. */
function directoryReady(exitCode) {
    return Number(exitCode) === 0
}
