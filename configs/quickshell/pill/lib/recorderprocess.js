.pragma library

/**
 * Build a SIGINT command for one known child process. Reject invalid PIDs
 * rather than letting a malformed value become a process-group signal.
 */
function interruptCommand(pid) {
    var value = Number(pid)
    if (!isFinite(value) || Math.floor(value) !== value || value <= 1)
        return []
    return ["kill", "-INT", String(value)]
}
