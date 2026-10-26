.pragma library

/*
 * Pure application-state policy shared by the launcher fan and Apps detail
 * view. The caller supplies observable facts; this module never inspects
 * Quickshell objects or mutates the registry/session.
 */
function deriveState(input) {
    var s = input || {};
    if (!s.exists)
        return "idle";
    if (s.stopping)
        return "stopping";
    if (s.failed)
        return "failed";
    if (Number(s.windowCount || 0) > 0)
        return "running";
    if (s.folderMissing)
        return "missing";
    if (s.needsSetup || !s.targetValid)
        return "setup";
    if (s.pending)
        return "preparing";
    if (s.launching)
        return "launching";
    if (s.waiting)
        return "waiting";
    return "idle";
}

function isActive(input) {
    var s = input || {};
    return Number(s.windowCount || 0) > 0 || s.processRunning === true;
}
