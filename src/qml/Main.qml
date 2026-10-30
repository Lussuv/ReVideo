import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Dialogs

ApplicationWindow {
    id: win

    readonly property int thumbCount: 12
    readonly property real trimPanelHeight: 164

    readonly property alias player: player
    readonly property Exporter exporter: Exporter {
        onFinished: error => {
            if (error)
                win.error = error
            else
                win.exportMenuOpen = false
        }
        onFrameSaved: error => {
            if (error)
                win.error = error
        }
    }
    readonly property Updater updater: Updater {
        onError: message => win.error = message
    }
    readonly property Thumbnailer thumbnailer: Thumbnailer {}
    readonly property var thumbnails: thumbnailer.thumbnails

    property bool loading: false
    property real position: 0
    property bool seeking: false
    /// While the mouse holds the seek bar or timeline: -1 no drag, 0/1 resume on release.
    property int resumeAfterDrag: -1
    /// Playhead position before a trim handle drag, restored on release; -1 if none.
    property real trimDragOrigin: -1
    property bool trimOpen: false
    property bool infoOpen: false
    property bool exportMenuOpen: false
    property real trimStart: 0
    property real trimEnd: 0
    /// 0 = Original, 1 = Discord
    property int preset: 0
    property string error: ""
    /// -1 closed, 0 "Abbrechen" chosen, 1 "Löschen" chosen
    property int deleteChoice: -1
    property string pendingDelete: ""
    property string pendingNext: ""
    property bool controlsHovered: false

    readonly property bool fullscreen: visibility === Window.FullScreen
    readonly property bool hasVideo: player.loaded
    readonly property real duration: player.duration
    readonly property real frame: 1 / (player.fps > 0 ? player.fps : 30)
    readonly property bool controlsVisible: controlsHovered || player.paused || hideTimer.running

    width: 1280
    height: 800
    minimumWidth: 960
    minimumHeight: 600
    title: "ReVideo"
    color: Theme.bg
    font.family: "Inter"

    Component.onCompleted: {
        // Window managers on Windows cascade new windows instead of centering them.
        x = Screen.virtualX + (Screen.width - width) / 2
        y = Screen.virtualY + (Screen.height - height) / 2
        visible = true
        player.volume = Util.savedVolume
        player.muted = Util.savedMuted
        if (Util.launchFile)
            load(Util.launchFile)
        updater.check()
    }

    function clamp(v, lo, hi) {
        return Math.min(Math.max(v, lo), hi)
    }
    function snap(sec) {
        return Util.snapToFrame(sec, frame)
    }
    function clearFocus() {
        contentItem.forceActiveFocus()
    }

    function load(path) {
        thumbnailer.cancel()
        trimOpen = false
        infoOpen = false
        exportMenuOpen = false
        position = 0
        error = ""
        loading = true
        player.load(path)
    }

    function setTrim(start, end) {
        const e = clamp(snap(end), frame, duration)
        trimStart = clamp(snap(start), 0, e - frame)
        trimEnd = e
    }

    /// Seeks to the frame at `sec`; with the trim panel open the playhead stays
    /// between the trim start and the last frame before the trim end.
    function seekTo(sec) {
        sec = clamp(snap(sec), 0, duration)
        if (trimOpen)
            sec = clamp(sec, trimStart, Math.max(trimEnd - frame, trimStart))
        player.seek(sec)
        position = sec
    }

    function pause() {
        if (!player.paused)
            player.paused = true
    }
    /// Keeps the video paused while the mouse holds the seek bar or timeline.
    function beginDrag() {
        seeking = true
        if (resumeAfterDrag < 0) {
            resumeAfterDrag = player.paused ? 0 : 1
            pause()
        }
    }
    function endDrag() {
        seeking = false
        if (resumeAfterDrag === 1)
            player.paused = false
        resumeAfterDrag = -1
    }

    function showControls() {
        hideTimer.restart()
    }
    function togglePlay() {
        if (!hasVideo)
            return
        if (player.eof) {
            // Continue from where the playhead was moved to, otherwise from the start.
            seekTo(position < duration - frame ? position : 0)
            player.paused = false
        } else {
            player.paused = !player.paused
        }
        showControls()
    }
    function skip(delta) {
        seekTo(position + delta)
        showControls()
    }
    function stepFrame(dir) {
        pause()
        seekTo(snap(position) + dir * frame)
    }
    function toggleFullscreen() {
        visibility = fullscreen ? Window.Windowed : Window.FullScreen
    }
    function setVolume(v) {
        player.volume = v
        if (v > 0)
            player.muted = false
    }
    function toggleMute() {
        player.muted = !player.muted
        saveSettings()
    }
    function saveSettings() {
        Util.saveSettings(player.volume, player.muted)
    }

    function navigate(dir) {
        if (!hasVideo)
            return
        const next = Util.adjacentVideo(player.path, dir, false)
        if (next)
            load(next)
    }

    // Shows the frame under the dragged handle: the first frame for the start,
    // the last frame inside the range for the end.
    function timelineTrim(start, end) {
        if (trimDragOrigin < 0)
            trimDragOrigin = position
        beginDrag()
        const startMoved = start !== trimStart
        setTrim(start, end)
        seekTo(startMoved ? trimStart : trimEnd - frame)
    }
    function timelineSeek(t) {
        beginDrag()
        seekTo(t)
    }
    // seekTo clamps into the new range: an origin outside of it lands on the first or last frame.
    function timelineRelease() {
        if (trimDragOrigin >= 0) {
            seekTo(trimDragOrigin)
            trimDragOrigin = -1
        }
        endDrag()
    }

    function updateLoop() {
        if (trimOpen)
            player.setLoop(trimStart, trimEnd)
        else
            player.setLoop(-1, -1)
    }
    onTrimOpenChanged: updateLoop()
    onTrimStartChanged: updateLoop()
    onTrimEndChanged: updateLoop()

    function openFile() {
        openDialog.open()
    }
    function startExport() {
        const original = preset === 0
        const ext = original ? (Util.suffix(player.path) || "mp4") : "mp4"
        exportDialog.nameFilters = [ext.toUpperCase() + " (*." + ext + ")"]
        exportDialog.currentFolder = Util.folderUrl(player.path)
        exportDialog.selectedFile = Util.siblingUrl(player.path,
            Util.baseName(player.path) + (original ? "_trimmed." : "_discord.") + ext)
        exportDialog.open()
    }
    function saveFrame() {
        // The saved frame is the one on screen when the button was pressed.
        pause()
        frameDialog.currentFolder = Util.folderUrl(player.path)
        frameDialog.selectedFile = Util.siblingUrl(player.path, Util.baseName(player.path) + "_frame.png")
        frameDialog.open()
    }

    function askDelete() {
        if (hasVideo && !exporter.running)
            deleteChoice = 1
    }
    function confirmDelete() {
        deleteChoice = -1
        pendingDelete = player.path
        pendingNext = Util.adjacentVideo(player.path, 1, true)
        thumbnailer.cancel()
        loading = true
        // mpv has to release the file first; Windows refuses to move open files.
        player.unload()
    }

    Connections {
        target: player
        function onFileLoaded() {
            win.loading = false
            win.trimStart = 0
            win.trimEnd = player.duration
            win.showControls()
            win.thumbnailer.start(player.path, player.duration, win.thumbCount)
        }
        function onLoadFailed(message) {
            win.loading = false
            win.error = message
        }
        function onNoAudioOutput() {
            win.error = "Keine Audioausgabe verfügbar. Wiedergabe ohne Ton."
        }
        function onPositionChanged() {
            if (win.seeking)
                return
            win.position = player.position
            // mpv loops at the trim end itself; this catches playback before the start.
            if (win.trimOpen && !player.paused && win.position < win.trimStart - 0.05)
                win.seekTo(win.trimStart)
        }
        function onEofChanged() {
            // A trim end at the very end of the file is reached as end of file.
            if (player.eof && win.trimOpen) {
                win.seekTo(win.trimStart)
                player.paused = false
            }
            if (player.eof)
                win.showControls()
        }
        function onClosed() {
            if (!win.pendingDelete)
                return
            const path = win.pendingDelete
            win.pendingDelete = ""
            const err = Util.moveToTrash(path)
            if (err) {
                win.load(path)
                win.error = err
            } else if (win.pendingNext) {
                win.load(win.pendingNext)
            } else {
                win.loading = false
            }
        }
    }

    Timer {
        id: hideTimer
        interval: 1800
    }

    FileDialog {
        id: openDialog
        title: "Video öffnen"
        nameFilters: ["Video (" + Util.videoExtensions.map(e => "*." + e).join(" ") + ")"]
        onAccepted: win.load(Util.urlToPath(selectedFile))
    }
    FileDialog {
        id: exportDialog
        title: "Export speichern"
        fileMode: FileDialog.SaveFile
        onAccepted: win.exporter.start(player.path, Util.urlToPath(selectedFile), win.trimStart,
                                       win.trimEnd, win.preset, player.hasAudio)
    }
    FileDialog {
        id: frameDialog
        title: "Frame speichern"
        fileMode: FileDialog.SaveFile
        nameFilters: ["PNG (*.png)"]
        onAccepted: win.exporter.saveFrame(player.path, win.snap(win.position), win.frame,
                                           Util.urlToPath(selectedFile))
    }

    Shortcut { sequence: "Space"; enabled: win.deleteChoice < 0; onActivated: win.togglePlay() }
    Shortcut { sequence: "Left"; enabled: win.deleteChoice < 0; onActivated: win.skip(-5) }
    Shortcut { sequence: "Right"; enabled: win.deleteChoice < 0; onActivated: win.skip(5) }
    Shortcut { sequence: ","; enabled: win.deleteChoice < 0; onActivated: win.stepFrame(-1) }
    Shortcut { sequence: "."; enabled: win.deleteChoice < 0; onActivated: win.stepFrame(1) }
    Shortcut { sequence: "Del"; enabled: win.deleteChoice < 0; onActivated: win.askDelete() }
    Shortcut { sequence: "F11"; enabled: win.deleteChoice < 0; onActivated: win.toggleFullscreen() }
    Shortcut {
        sequence: "Esc"
        enabled: win.deleteChoice >= 0 || win.fullscreen
        onActivated: {
            if (win.deleteChoice >= 0)
                win.deleteChoice = -1
            else
                win.toggleFullscreen()
        }
    }
    Shortcut { sequence: "Left"; enabled: win.deleteChoice >= 0; onActivated: win.deleteChoice = 0 }
    Shortcut { sequence: "Right"; enabled: win.deleteChoice >= 0; onActivated: win.deleteChoice = 1 }
    Shortcut {
        sequences: ["Return", "Enter"]
        enabled: win.deleteChoice >= 0
        onActivated: {
            if (win.deleteChoice === 1)
                win.confirmDelete()
            else
                win.deleteChoice = -1
        }
    }

    TopBar {
        id: topBar
        app: win
        visible: !win.fullscreen
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: visible ? implicitHeight : 0
    }

    Item {
        id: body
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: topBar.bottom
        anchors.bottom: parent.bottom

        // The video runs edge to edge; only the trim panel keeps a margin. mpv needs
        // its render context before the first file, so the surface always exists.
        Item {
            id: stage
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: trimPanel.visible ? trimPanel.top : parent.bottom
            anchors.bottomMargin: trimPanel.visible ? 16 : 0

            MpvItem {
                id: player
                anchors.fill: parent
                // Letterbox space shows the page surface; only fullscreen keeps black, as players do.
                background: win.fullscreen ? "black" : Theme.bg
            }
            MouseArea {
                anchors.fill: parent
                enabled: win.hasVideo
                hoverEnabled: true
                onPositionChanged: win.showControls()
                onPressed: win.clearFocus()
                onClicked: win.togglePlay()
                onDoubleClicked: win.toggleFullscreen()
            }
            Controls {
                app: win
                visible: win.hasVideo && win.controlsVisible
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 16
            }
        }

        TrimPanel {
            id: trimPanel
            app: win
            visible: win.hasVideo && win.trimOpen && !win.fullscreen
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 16
            height: win.trimPanelHeight
        }

        Rectangle {
            anchors.fill: parent
            visible: !win.hasVideo
            color: Theme.bg

            Text {
                anchors.centerIn: parent
                visible: win.loading
                text: "Video wird geöffnet …"
                color: Theme.tx3
                font.pixelSize: 15
            }
            Column {
                anchors.centerIn: parent
                visible: !win.loading
                spacing: 6
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Nichts geladen."
                    color: Theme.tx
                    font.pixelSize: 32
                    font.weight: Font.DemiBold
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Video öffnen, um zu starten."
                    color: Theme.tx2
                    font.pixelSize: 17
                }
                Item { width: 1; height: 12 }
                Btn {
                    anchors.horizontalCenter: parent.horizontalCenter
                    variant: "primary"
                    iconName: "folder"
                    iconSize: 18
                    text: "Datei öffnen"
                    fontSize: 15
                    verticalPadding: 10
                    horizontalPadding: 18
                    onClicked: win.openFile()
                }
            }
        }

        // Popovers close on any click outside of them.
        MouseArea {
            anchors.fill: parent
            visible: win.infoOpen && win.hasVideo && !win.fullscreen
            onClicked: win.infoOpen = false
        }
        InfoPopover {
            app: win
            visible: win.infoOpen && win.hasVideo && !win.fullscreen
            x: topBar.infoX
            y: 4
        }

        MouseArea {
            anchors.fill: parent
            visible: win.exportMenuOpen && win.trimOpen && win.hasVideo && !win.fullscreen
            onClicked: win.exportMenuOpen = false
        }
        ExportMenu {
            app: win
            visible: win.exportMenuOpen && win.trimOpen && win.hasVideo && !win.fullscreen
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.rightMargin: 32
            anchors.bottomMargin: 16 + win.trimPanelHeight + 8
        }

        Sheet {
            visible: win.error !== ""
            anchors.horizontalCenter: parent.horizontalCenter
            y: 24
            width: Math.min(640, toastText.implicitWidth + 32)
            height: toastText.implicitHeight + 24
            border.color: Theme.err

            Text {
                id: toastText
                anchors.fill: parent
                anchors.margins: 12
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                text: win.error
                color: Theme.tx
                font.pixelSize: 14
                wrapMode: Text.Wrap
            }
            MouseArea {
                anchors.fill: parent
                onClicked: win.error = ""
            }
        }
    }

    DeleteDialog {
        app: win
        anchors.fill: parent
        visible: win.deleteChoice >= 0 && win.hasVideo
    }
}
