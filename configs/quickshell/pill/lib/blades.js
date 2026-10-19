.pragma library

/*
 * Which registry records belong on the blade fan, and in what order.
 *
 * Pure functions on plain records so the rule can be unit-tested without
 * Quickshell (tests/test_blades.js). The blades are the games and Wine apps
 * fan, so the default rule is exactly that; the per-app `blade` field is the
 * user's override:
 *
 *   "auto"  games and Wine-family apps appear (the default)
 *   "pin"   always appears, whatever it is
 *   "hide"  never appears
 */

var AUTO_RUNNERS = ["wine", "wine-staging", "umu", "steam"];

function lower(v) {
    return String(v === undefined || v === null ? "" : v).toLowerCase();
}

/*
 * Turn identity-bearing strings into comparable keys without making matching
 * depend on display punctuation or filename suffixes. Keep matching exact:
 * loose substring matching can make two unrelated games activate each other.
 */
function identity(v) {
    return lower(v).trim()
        .replace(/\.desktop$/i, "")
        .replace(/\.exe$/i, "")
        .replace(/[^a-z0-9]+/g, "");
}

function identityTail(v) {
    var s = lower(v).trim().replace(/\.desktop$/i, "").replace(/\.exe$/i, "");
    var parts = s.split(/[./\\\\]/);
    return identity(parts.length > 0 ? parts[parts.length - 1] : s);
}

function basename(v) {
    var s = String(v === undefined || v === null ? "" : v);
    var parts = s.split(/[\\\\/]/);
    return parts.length > 0 ? parts[parts.length - 1] : s;
}

/*
 * Match a registry app to a live Hyprland window. The same registry ID is used
 * for launching, while a real window may expose a desktop ID, WM class,
 * executable name, or an exact title. Don't use fuzzy includes: that is unsafe
 * for similarly named games and utilities.
 */
function matchesWindow(app, window, entry) {
    if (!app || !window)
        return false;

    var clsKey = identity(window.cls || window.appId || window.className || "");
    if (clsKey) {
        var candidates = [
            app.id,
            app.name,
            app.desktopEntryId,
            entry && entry.id,
            entry && entry.startupClass,
            entry && entry.name,
            basename(app.executable || "")
        ];
        for (var i = 0; i < candidates.length; ++i) {
            var full = identity(candidates[i]);
            var tail = identityTail(candidates[i]);
            if (full && clsKey === full)
                return true;
            if (tail && clsKey === tail)
                return true;
        }
    }

    var titleKey = identity(window.title || "");
    if (!titleKey)
        return false;
    var titleCandidates = [app.name, entry && entry.name];
    for (var j = 0; j < titleCandidates.length; ++j) {
        var titleCandidate = identity(titleCandidates[j]);
        if (titleCandidate && titleKey === titleCandidate)
            return true;
    }
    return false;
}

/*
 * Select the next window for a click on an app blade. Clicking an app whose
 * window is already focused cycles to the next one; otherwise choose the first
 * non-minimized window. If every window is minimized, return the first so the
 * caller can restore it.
 */
function nextWindow(windows, activeAddress) {
    if (!windows || windows.length === 0)
        return null;

    function addressKey(v) {
        return lower(v).replace(/^0x/, "");
    }

    var active = addressKey(activeAddress);
    var at = -1;
    if (active) {
        for (var i = 0; i < windows.length; ++i) {
            if (addressKey(windows[i] && windows[i].address) === active) {
                at = i;
                break;
            }
        }
    }
    if (at >= 0)
        return windows[(at + 1) % windows.length];

    for (var j = 0; j < windows.length; ++j) {
        if (String(windows[j] && windows[j].workspace || "") !== "special:minimized")
            return windows[j];
    }
    return windows[0];
}

/** A persisted blade override is deliberately normalized to a small closed set. */
function mode(app) {
    var m = lower(app && app.blade);
    return m === "pin" || m === "hide" ? m : "auto";
}

function eligible(app) {
    if (!app || !app.id)
        return false;
    var m = mode(app);
    if (m === "hide")
        return false;
    if (m === "pin")
        return true;
    return lower(app.category) === "game" || AUTO_RUNNERS.indexOf(lower(app.runner)) >= 0;
}

/**
 * Stable ordering: explicit pin/favourite priority is preserved, but merely
 * launching a game no longer reshuffles the fan. Existing bladeOrder wins;
 * legacy records fall back to createdAt and then their name for deterministic
 * migration from the older registry schema.
 */
function compare(a, b) {
    var ap = mode(a) === "pin" ? 1 : 0;
    var bp = mode(b) === "pin" ? 1 : 0;
    if (ap !== bp)
        return bp - ap;

    var af = a.favorite ? 1 : 0;
    var bf = b.favorite ? 1 : 0;
    if (af !== bf)
        return bf - af;

    var ao = Number(a.bladeOrder);
    var bo = Number(b.bladeOrder);
    if (isFinite(ao) && isFinite(bo) && ao !== bo)
        return ao - bo;

    var ac = Number(a.createdAt || 0);
    var bc = Number(b.createdAt || 0);
    if (ac !== bc)
        return ac - bc;

    var an = lower(a.name);
    var bn = lower(b.name);
    return an < bn ? -1 : (an > bn ? 1 : 0);
}

/**
 * Balance all apps across concentric blade rings. Each ring is capped at
 * maxPerRing so adjacent capsules retain enough angular separation to avoid
 * collisions. The number of entries per ring differs by at most one.
 *
 * Output is an array of {index, ring, ringSize, slot, angle}; index remains
 * aligned with the stable app order supplied by the caller.
 */
function layout(count, maxPerRing) {
    var n = Math.max(0, Math.floor(Number(count) || 0));
    var limit = Math.max(2, Math.floor(Number(maxPerRing) || 6));
    if (n === 0)
        return [];

    var rings = Math.ceil(n / limit);
    var base = Math.floor(n / rings);
    var extra = n % rings;
    var out = [];
    var index = 0;

    for (var ring = 0; ring < rings; ++ring) {
        var size = base + (ring < extra ? 1 : 0);
        for (var slot = 0; slot < size; ++slot) {
            out.push({
                index: index++,
                ring: ring,
                ringCount: rings,
                ringSize: size,
                slot: slot,
                angle: size <= 1 ? 43 : 8 + 70 * slot / (size - 1)
            });
        }
    }
    return out;
}

/** A regular workspace is eligible only when its name/id is non-special and id is positive when provided. */
function usableWorkspace(workspace) {
    if (!workspace)
        return false;
    var name = String(workspace.name === undefined ? "" : workspace.name);
    if (name.toLowerCase().indexOf("special:") === 0)
        return false;
    if (workspace.id !== undefined && workspace.id !== null && Number(workspace.id) <= 0)
        return false;
    return name.length > 0 || Number(workspace.id) > 0;
}

function workspaceKey(workspace) {
    if (!workspace)
        return "";
    if (workspace.id !== undefined && workspace.id !== null && Number(workspace.id) > 0)
        return String(Number(workspace.id));
    return String(workspace.name || "");
}

/**
 * Choose a genuinely empty regular workspace on the requested monitor.
 * Occupancy and reservations are keyed by workspace name or id. No workspace
 * is created here; null means the caller must wait rather than launch.
 */
function chooseEmptyWorkspace(workspaces, windows, reservations, monitorName) {
    var occupied = {};
    var reserved = reservations || {};
    var list = workspaces || [];
    var wins = windows || [];

    for (var i = 0; i < wins.length; ++i) {
        var w = wins[i];
        if (!w)
            continue;
        var key = String(w.workspaceId && Number(w.workspaceId) > 0 ? Number(w.workspaceId) : (w.workspace || ""));
        if (key.length > 0)
            occupied[key] = true;
    }

    var candidates = [];
    for (var j = 0; j < list.length; ++j) {
        var ws = list[j];
        if (!usableWorkspace(ws))
            continue;
        if (monitorName && monitorName.length > 0 && String(ws.monitor || "") !== monitorName)
            continue;
        var key = workspaceKey(ws);
        if (!key || occupied[key] || reserved[key])
            continue;
        candidates.push(ws);
    }

    candidates.sort(function(a, b) {
        var ai = Number(a.id || 0);
        var bi = Number(b.id || 0);
        if (ai && bi && ai !== bi)
            return ai - bi;
        return String(a.name || "").localeCompare(String(b.name || ""));
    });
    return candidates.length > 0 ? candidates[0] : null;
}

/** At most `max` eligible records in blade order; `max` <= 0 means no cap. */
function select(apps, max) {
    var out = [];
    for (var i = 0; i < (apps ? apps.length : 0); i++)
        if (eligible(apps[i]))
            out.push(apps[i]);
    out.sort(compare);
    return max > 0 ? out.slice(0, max) : out;
}
