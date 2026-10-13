.pragma library

/** Return a concrete Linux V4L2 node only when the selected Qt device ID names one. */
function v4l2Path(deviceId) {
    var id = String(deviceId || "")
    var match = id.match(/\/dev\/video[0-9]+(?=$|[?#])/)
    return match ? match[0].replace(/[?#].*$/, "") : ""
}

/** Screen-camera capture needs the camera to survive closing its UI while screen recording continues. */
function shouldKeepScreenCamera(screenCameraMode, screenRecording) {
    return !!screenCameraMode && !!screenRecording
}

/** A camera cannot be deactivated while capture is starting or output is being finalized. */
function shouldDeferCameraStop(videoRecording, capturingPhoto, startingVideo) {
    return !!videoRecording || !!capturingPhoto || !!startingVideo
}

/** Close only after a requested stop is pending and all capture work is finished. */
function shouldFinishPendingCameraStop(stopPending, videoRecording, capturingPhoto, startingVideo) {
    return !!stopPending && !videoRecording && !capturingPhoto && !startingVideo
}
