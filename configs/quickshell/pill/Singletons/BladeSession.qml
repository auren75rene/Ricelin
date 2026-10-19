pragma Singleton
import QtQuick
import Quickshell

/**
 * Session-only coordination shared by each per-monitor BladeLayer. The app
 * registry is persisted; queue state, workspace reservations and live process
 * lifecycle state are deliberately transient. Sharing these maps prevents two
 * monitor-local fans from claiming the same empty workspace or queueing the
 * same game independently.
 */
Singleton {
    id: root

    property var queuedIds: ({})                 // app ID -> { requestedAt, monitor }
    property var reservedWorkspaces: ({})        // workspace key -> app ID
    property var launchTargets: ({})             // app ID -> { workspaceId, workspaceName, monitor, key, startedAt }
    property var stoppingIds: ({})               // app ID -> request timestamp
    property var failedIds: ({})                 // app ID -> readable failure
    property var monitorFallbackNotified: ({})   // app ID -> true
}
