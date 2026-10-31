import QtCore
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Dialogs

ApplicationWindow {
    id: win

    readonly property int thumbCount: 12
    readonly property real trimPanelHeight: 164 + (clipsOpen ? 14 + trimPanel.clipAreaHeight : 0)

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
    /// One audio player per music track.
    readonly property Instantiator musicPlayers: Instantiator {
        model: win.musicTracks.length
        delegate: MusicPlayer {}
    }
    readonly property Prober prober: Prober {
        onProbed: (path, info) => win.clipProbed(path, info)
    }
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
    property bool updatePromptDismissed: false

    /// Clips joined on export; the trim panel edits the one at `currentClip`.
    readonly property ListModel clips: ListModel {}
    property bool clipsOpen: false
    property int currentClip: -1
    // Derived from `clips` by refreshClips(); ListModel contents do not notify bindings.
    property real clipsTotal: 0
    property var clipLengths: []
    property int clipsPending: 0
    property bool clipsMatch: true
    /// Between two clips mpv reports no file; the UI stays as it is meanwhile.
    property bool switchingClip: false
    /// Grey stand-in tiles while files are dragged over the strip; index -1: none.
    property int placeholderIndex: -1
    property int placeholderCount: 0
    /// Where the clips chosen in the file dialog go.
    property int clipInsertIndex: 0
    /// Music tracks under the clips, each a list of pieces sorted by offset: { path, name,
    /// duration (the whole song), peaks (loudest sample per 1/20 s, 0..1), start and length
    /// (the part of the song; length 0 while it is read), offset (where `start` plays on the
    /// joined timeline; negative: cut off), volume }. Anything beyond the clips is cut.
    /// Changed only by replacing the array, so that bindings see it.
    property var musicTracks: []
    readonly property bool hasMusic: musicTracks.length > 0
    onMusicTracksChanged: syncMusic()
    onSwitchingClipChanged: syncMusic()
    /// Razor tool: a click cuts the clip or music piece under the mouse.
    property bool cutMode: false
    /// No clip selected: the whole timeline plays, all clips back to back.
    readonly property bool sequenceMode: clipsOpen && currentClip < 0 && clips.count > 0
    /// Sequence entry the shown position belongs to: changes only once the next clip is
    /// loaded (or a seek heads there), so that index and position always match.
    property int sequenceIndex: -1
    /// Clip under the playhead and the playhead on the joined timeline.
    readonly property int timelineIndex: sequenceMode ? sequenceIndex : currentClip
    readonly property real timelinePosition: timelineIndex >= 0 && timelineIndex < clips.count
        ? clipOffset(timelineIndex) + position - clips.get(timelineIndex).start : 0
    /// Position in sequence entry `pendingIndex` to seek to once it is loaded; -1 none.
    property real pendingSeek: -1
    property int pendingIndex: -1
    /// Clips the running sequence was built from, to notice changes.
    property string sequenceKey: ""

    /// A clip is muted; even a single one then goes through the clip export.
    property bool clipsMuted: false
    readonly property bool joining: clipsOpen && (clips.count > 1 || hasMusic || clipsMuted)
    readonly property bool updatePromptOpen: updater.available && !updater.busy && !updatePromptDismissed

    readonly property bool fullscreen: visibility === Window.FullScreen
    readonly property bool hasVideo: player.loaded || switchingClip || sequenceMode
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
        closeClips()
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
        if (sequenceMode)
            seekTimeline(timelinePosition + delta)
        else
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
        // The whole timeline runs through all clips instead.
        if (trimOpen && !sequenceMode)
            player.setLoop(trimStart, trimEnd)
        else
            player.setLoop(-1, -1)
    }
    onTrimOpenChanged: updateLoop()
    onTrimStartChanged: {
        updateLoop()
        syncClip("start", trimStart)
    }
    onTrimEndChanged: {
        updateLoop()
        syncClip("end", trimEnd)
    }

    function clipEntry(path) {
        return { path: path, name: Util.fileName(path), ready: false, duration: 0, start: 0, end: 0,
                 width: 0, height: 0, fps: 0, hasAudio: false, muted: false, signature: "", thumb: "" }
    }
    /// Opens the clip strip with the current video as the first clip.
    function openClips() {
        clips.clear()
        const first = clipEntry(player.path)
        first.start = trimStart
        first.end = trimEnd
        clips.append(first)
        currentClip = 0
        clipsOpen = true
        refreshClips()
        prober.probe(player.path)
    }
    /// The video on screen stays loaded with its trim.
    function closeClips() {
        player.setAudioOff(false)
        musicTracks = []
        cutMode = false
        placeholderIndex = -1
        placeholderCount = 0
        clipsOpen = false
        clips.clear()
        currentClip = -1
        refreshClips()
    }
    /// Inserts the video files among `paths` before `index`.
    function isVideo(path) {
        return Util.videoExtensions.includes(Util.suffix(path).toLowerCase())
    }
    function addClips(paths, index) {
        for (const path of paths) {
            if (!isVideo(path))
                continue
            clips.insert(index, clipEntry(path))
            if (index <= currentClip)
                currentClip++
            index++
            prober.probe(path)
        }
        refreshClips()
    }
    function clipProbed(path, info) {
        if (musicTracks.some(pieces => pieces.some(p => p.path === path && p.length === 0))) {
            const ok = info.duration > 0 && info.hasAudio
            if (!ok)
                error = Util.fileName(path) + " enthält keinen lesbaren Ton."
            musicTracks = musicTracks
                .map(pieces => pieces
                     .filter(p => ok || p.path !== path || p.length > 0)
                     .map(p => p.path === path && p.length === 0
                          ? Object.assign({}, p, { duration: info.duration, length: info.duration, peaks: info.peaks ?? [] })
                          : p))
                .filter(pieces => pieces.length > 0)
            clampMusic()
        }
        for (let i = clips.count - 1; i >= 0; i--) {
            const c = clips.get(i)
            if (c.path !== path || c.ready)
                continue
            if (info.duration === undefined || !info.hasVideo) {
                error = Util.fileName(path) + " enthält kein lesbares Video."
                removeClip(i)
                continue
            }
            clips.set(i, { ready: true, duration: info.duration, width: info.width, height: info.height,
                           fps: info.fps, hasAudio: info.hasAudio, signature: info.signature,
                           thumb: info.thumb, end: c.end > 0 ? c.end : info.duration })
        }
        refreshClips()
    }
    function removeClip(i) {
        if (clips.count < 2)
            return
        clips.remove(i)
        if (i < currentClip) {
            currentClip--
        } else if (i === currentClip) {
            currentClip = -1
            selectClip(Math.min(i, clips.count - 1))
        }
        refreshClips()
    }
    /// Moves clip `from` to index `dest`.
    function moveClip(from, dest) {
        if (dest === from)
            return
        clips.move(from, dest, 1)
        if (currentClip === from)
            currentClip = dest
        else if (from < currentClip && dest >= currentClip)
            currentClip--
        else if (from > currentClip && dest <= currentClip)
            currentClip++
    }
    /// Puts `n` placeholders (entries without path) at `i`, one per file being dragged in.
    function showPlaceholder(i, n) {
        if (placeholderIndex === i && placeholderCount === n)
            return
        hidePlaceholder()
        for (let k = 0; k < n; k++)
            clips.insert(i, clipEntry(""))
        if (i <= currentClip)
            currentClip += n
        placeholderIndex = i
        placeholderCount = n
        refreshClips()
    }
    function hidePlaceholder() {
        if (placeholderIndex < 0)
            return
        clips.remove(placeholderIndex, placeholderCount)
        if (placeholderIndex < currentClip)
            currentClip -= placeholderCount
        placeholderIndex = -1
        placeholderCount = 0
        refreshClips()
    }
    /// Loads the clip into the player; onFileLoaded restores its trim.
    function selectClip(i) {
        if (i === currentClip)
            return
        currentClip = i
        thumbnailer.cancel()
        exportMenuOpen = false
        loading = true
        switchingClip = true
        // load() starts playback; a paused video stays paused on the next clip.
        const paused = player.paused
        player.load(clips.get(i).path, clips.get(i).start)
        player.paused = paused
        player.setAudioOff(clips.get(i).muted)
    }
    function toggleClipMute(i) {
        clips.setProperty(i, "muted", !clips.get(i).muted)
        refreshClips()
        if (i === currentClip)
            player.setAudioOff(clips.get(i).muted)
    }
    function syncClip(role, value) {
        // While another clip loads, the trim still belongs to the previous one.
        if (!clipsOpen || loading || currentClip < 0)
            return
        clips.setProperty(currentClip, role, value)
        refreshClips()
    }
    function refreshClips() {
        let total = 0, pending = 0, match = true
        const lengths = []
        for (let i = 0; i < clips.count; i++) {
            const c = clips.get(i)
            lengths.push(Math.max(c.end - c.start, 0))
            total += lengths[i]
            if (!c.ready)
                pending++
            if (c.signature !== clips.get(0).signature)
                match = false
        }
        clipsTotal = total
        clipLengths = lengths
        clipsPending = pending
        clipsMatch = match
        let muted = false
        for (let i = 0; i < clips.count; i++)
            muted = muted || clips.get(i).muted
        clipsMuted = muted
        if (sequenceMode)
            Qt.callLater(rebuildSequence)
        clampMusic()
    }
    function isAudio(path) {
        return ["mp3", "m4a", "aac", "wav", "flac", "ogg", "opus", "wma"].includes(Util.suffix(path).toLowerCase())
    }
    /// Every song gets a track of its own, below the others.
    function addMusic(paths) {
        const added = paths.filter(isAudio).map(path => [{
            path: path, name: Util.fileName(path), duration: 0, peaks: [], start: 0, length: 0, offset: 0, volume: 1
        }])
        if (added.length === 0)
            return
        musicTracks = musicTracks.concat(added)
        for (const track of added)
            prober.probe(track[0].path)
    }
    /// Replaces track `k` by `change(copy of its pieces)`; empty tracks disappear.
    function changeTrack(k, change) {
        const tracks = musicTracks.slice()
        tracks[k] = change(tracks[k].slice())
        musicTracks = tracks.filter(pieces => pieces.length > 0)
    }
    function removePiece(k, i) {
        changeTrack(k, pieces => {
            pieces.splice(i, 1)
            return pieces
        })
    }
    function setPieceVolume(k, i, volume) {
        changeTrack(k, pieces => {
            pieces[i] = Object.assign({}, pieces[i], { volume: volume })
            return pieces
        })
    }
    /// Moves a piece to `offset`, stopping at its neighbours on the track.
    function movePiece(k, i, offset) {
        changeTrack(k, pieces => {
            const p = pieces[i], prev = pieces[i - 1], next = pieces[i + 1]
            offset = clampPiece(offset, p.length)
            if (prev)
                offset = Math.max(offset, prev.offset + prev.length)
            if (next)
                offset = Math.min(offset, next.offset - p.length)
            pieces[i] = Object.assign({}, p, { offset: offset })
            return pieces
        })
    }
    /// Splits piece `i` of track `k` at `t` on the joined timeline.
    function cutPiece(k, i, t) {
        changeTrack(k, pieces => {
            const p = pieces[i], head = t - p.offset
            if (head < 0.05 || p.length - head < 0.05)
                return pieces
            pieces.splice(i, 1, Object.assign({}, p, { length: head }),
                          Object.assign({}, p, { start: p.start + head, length: p.length - head, offset: t }))
            return pieces
        })
    }
    /// Splits clip `i` at `t` (in its file) into two clips.
    function cutClip(i, t) {
        const c = clips.get(i)
        t = Util.snapToFrame(t, 1 / (c.fps > 0 ? c.fps : 30))
        if (t - c.start < 0.05 || c.end - t < 0.05)
            return
        const tail = { path: c.path, name: c.name, ready: c.ready, duration: c.duration, start: t, end: c.end,
                       width: c.width, height: c.height, fps: c.fps, hasAudio: c.hasAudio,
                       muted: c.muted, signature: c.signature, thumb: c.thumb }
        // The open clip keeps the head: its trim end moves, syncClip() stores it.
        if (i === currentClip)
            trimEnd = t
        else
            clips.setProperty(i, "end", t)
        clips.insert(i + 1, tail)
        if (i + 1 <= currentClip)
            currentClip++
        refreshClips()
    }
    function pickMusic() {
        musicDialog.currentFolder = StandardPaths.writableLocation(StandardPaths.MusicLocation)
        musicDialog.open()
    }
    /// Keeps at least a second of a piece `length` long under the clips.
    function clampPiece(offset, length) {
        return clamp(offset, Math.min(1 - length, 0), Math.max(clipsTotal - 1, 0))
    }
    function clampMusic() {
        const tracks = musicTracks.map(pieces => pieces.map(p => {
            const offset = p.length > 0 ? clampPiece(p.offset, p.length) : p.offset
            return offset === p.offset ? p : Object.assign({}, p, { offset: offset })
        }))
        if (tracks.some((pieces, k) => pieces.some((p, i) => p !== musicTracks[k][i])))
            musicTracks = tracks
    }
    function musicList() {
        const list = []
        for (const pieces of musicTracks)
            for (const p of pieces)
                list.push({ path: p.path, offset: p.offset, volume: p.volume, start: p.start, length: p.length })
        return list
    }
    /// Where clip `i` begins on the joined timeline.
    function clipOffset(i) {
        let t = 0
        for (let k = 0; k < i; k++)
            t += clipLengths[k] ?? 0
        return t
    }
    /// Lets the music follow the video: the playhead in the current clip, mapped onto the
    /// joined timeline and from there into the song.
    function syncMusic() {
        if (timelineIndex < 0 || timelineIndex >= clips.count)
            return
        // Between two clips of the timeline the music just runs on.
        if (sequenceMode && (!player.loaded || player.playlistPos !== sequenceIndex))
            return
        const t = clipOffset(timelineIndex) + player.position - clips.get(timelineIndex).start
        const playing = player.loaded && !player.paused && !switchingClip
        const base = player.muted ? 0 : player.volume
        for (let k = 0; k < musicTracks.length; k++) {
            const out = musicPlayers.objectAt(k)
            if (!out)
                continue
            const p = musicTracks[k].find(p => p.length > 0 && t >= p.offset && t < p.offset + p.length)
            out.volume = base * (p ? p.volume : 1)
            out.sync(p ? p.path : "", p ? p.start + t - p.offset : 0, playing)
        }
    }
    /// Deselects the clips and plays the whole timeline from where the playhead is.
    function showSequence() {
        if (!clipsOpen || clips.count === 0 || sequenceMode)
            return
        if (clipsPending > 0) {
            error = "Die Clips werden noch gelesen, bitte kurz warten."
            return
        }
        const t = timelinePosition
        currentClip = -1
        thumbnailer.cancel()
        exportMenuOpen = false
        loading = true
        sequenceKey = clipKey()
        player.loadSequence(clipList())
        seekTimeline(t)
    }
    function clipKey() {
        return clipList().map(c => c.path + "|" + c.start + "|" + c.end + "|" + c.muted).join("\n")
    }
    /// After clips changed while the timeline plays: the same spot in the new order.
    function rebuildSequence() {
        if (!sequenceMode || placeholderIndex >= 0 || clipsPending > 0 || clipKey() === sequenceKey)
            return
        const t = Math.min(timelinePosition, clipsTotal)
        sequenceKey = clipKey()
        player.loadSequence(clipList())
        seekTimeline(t)
    }
    /// Seeks to `t` on the joined timeline, switching clips if needed.
    function seekTimeline(t) {
        t = clamp(t, 0, Math.max(clipsTotal - frame, 0))
        let i = 0
        while (i < clips.count - 1 && t >= clipOffset(i + 1))
            i++
        const local = clips.get(i).start + t - clipOffset(i)
        if (i === sequenceIndex && i === player.playlistPos && !loading) {
            player.seek(local)
            position = local
        } else {
            pendingSeek = local
            pendingIndex = i
            sequenceIndex = i
            position = local
            player.playIndex(i)
        }
    }
    function clipList() {
        const list = []
        for (let i = 0; i < clips.count; i++) {
            const c = clips.get(i)
            list.push({ path: c.path, start: c.start, end: c.end, hasAudio: c.hasAudio, muted: c.muted,
                        signature: c.signature, width: c.width, height: c.height, fps: c.fps })
        }
        return list
    }

    function openFile() {
        openDialog.currentFolder = videosFolder()
        openDialog.open()
    }
    function startExport() {
        if (joining && (clipsPending > 0 || musicTracks.some(pieces => pieces.some(p => p.length === 0)))) {
            error = "Die Clips werden noch gelesen, bitte kurz warten."
            return
        }
        const original = preset === 0
        const source = joining ? clips.get(0).path : player.path
        // Only a lossless join keeps the container; a re-encode always writes MP4.
        const ext = original && (!joining || clipsMatch) ? (Util.suffix(source) || "mp4") : "mp4"
        exportDialog.nameFilters = [ext.toUpperCase() + " (*." + ext + ")"]
        exportDialog.currentFolder = Util.folderUrl(source)
        exportDialog.selectedFile = Util.siblingUrl(source, Util.baseName(source)
            + (!original ? "_discord." : joining ? "_joined." : "_trimmed.") + ext)
        exportDialog.open()
    }
    /// Open dialogs always start in the system's video folder.
    function videosFolder() {
        return StandardPaths.writableLocation(StandardPaths.MoviesLocation)
    }
    function pickClips(index) {
        clipInsertIndex = index
        clipDialog.currentFolder = videosFolder()
        clipDialog.open()
    }
    function saveFrame() {
        // The saved frame is the one on screen when the button was pressed.
        pause()
        frameDialog.currentFolder = Util.folderUrl(player.path)
        frameDialog.selectedFile = Util.siblingUrl(player.path, Util.baseName(player.path) + "_frame.png")
        frameDialog.open()
    }

    function installUpdate() {
        updatePromptDismissed = true
        updater.install()
    }

    function askDelete() {
        // In the clip strip, deleting only takes the clip out; the file stays.
        if (sequenceMode)
            return
        if (clipsOpen) {
            if (clips.count > 1)
                removeClip(currentClip)
            else
                closeClips()
            return
        }
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
            // A sequence entry: mpv plays it within its range already.
            if (win.sequenceMode) {
                const s = win.clips.get(player.playlistPos)
                win.loading = false
                win.trimStart = s ? s.start : 0
                win.trimEnd = s ? s.end : player.duration
                if (win.pendingSeek >= 0 && player.playlistPos === win.pendingIndex) {
                    player.seek(win.pendingSeek)
                    win.position = win.pendingSeek
                    win.pendingSeek = -1
                } else {
                    win.position = win.trimStart
                }
                win.sequenceIndex = player.playlistPos
                return
            }
            // A clip from the strip comes back with its own trim.
            const c = win.clipsOpen && win.currentClip >= 0 ? win.clips.get(win.currentClip) : null
            const start = c ? Math.min(c.start, player.duration) : 0
            const end = c && c.end > start ? Math.min(c.end, player.duration) : player.duration
            win.loading = false
            win.switchingClip = false
            win.trimStart = start
            win.trimEnd = end
            // mpv drops the loop on load; with unchanged values nothing would set it again.
            win.updateLoop()
            // mpv opened the clip at its start already; a seek would decode again.
            if (c)
                win.position = start
            win.showControls()
            win.thumbnailer.start(player.path, player.duration, win.thumbCount)
        }
        function onLoadFailed(message) {
            win.loading = false
            win.switchingClip = false
            win.error = message
        }
        function onNoAudioOutput() {
            win.error = "Keine Audioausgabe verfügbar. Wiedergabe ohne Ton."
        }
        function onPositionChanged() {
            win.syncMusic()
            if (win.seeking)
                return
            win.position = player.position
            // mpv loops at the trim end itself; this catches playback before the start.
            if (win.trimOpen && !win.sequenceMode && !player.paused && win.position < win.trimStart - 0.05)
                win.seekTo(win.trimStart)
        }
        function onPausedChanged() {
            win.syncMusic()
        }
        function onEofChanged() {
            // The end of the whole timeline starts it over.
            if (player.eof && win.sequenceMode) {
                win.seekTimeline(0)
                player.paused = false
            } else if (player.eof && win.trimOpen) {
                // A trim end at the very end of the file is reached as end of file.
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
        onAccepted: {
            const output = Util.urlToPath(selectedFile)
            if (win.joining)
                win.exporter.startSequence(win.clipList(), output, win.preset, win.musicList())
            else
                win.exporter.start(player.path, output, win.trimStart, win.trimEnd, win.preset, player.hasAudio)
        }
    }
    FileDialog {
        id: musicDialog
        title: "Musik wählen"
        fileMode: FileDialog.OpenFiles
        nameFilters: ["Audio (*.mp3 *.m4a *.aac *.wav *.flac *.ogg *.opus *.wma)"]
        onAccepted: {
            const paths = []
            for (let i = 0; i < selectedFiles.length; i++)
                paths.push(Util.urlToPath(selectedFiles[i]))
            win.addMusic(paths)
        }
    }
    FileDialog {
        id: clipDialog
        title: "Clips hinzufügen"
        fileMode: FileDialog.OpenFiles
        nameFilters: openDialog.nameFilters
        onAccepted: {
            const paths = []
            for (let i = 0; i < selectedFiles.length; i++)
                paths.push(Util.urlToPath(selectedFiles[i]))
            win.addClips(paths, Math.min(win.clipInsertIndex, win.clips.count))
        }
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
        sequence: "C"
        enabled: win.clipsOpen && win.trimOpen && win.deleteChoice < 0
        onActivated: win.cutMode = !win.cutMode
    }
    Shortcut { sequence: "V"; enabled: win.cutMode; onActivated: win.cutMode = false }
    Shortcut {
        sequence: "Esc"
        enabled: win.updatePromptOpen || win.deleteChoice >= 0 || win.cutMode || win.fullscreen
                 || win.clipsOpen && win.currentClip >= 0
        onActivated: {
            if (win.cutMode)
                win.cutMode = false
            else if (win.updatePromptOpen)
                win.updatePromptDismissed = true
            else if (win.deleteChoice >= 0)
                win.deleteChoice = -1
            else if (win.fullscreen)
                win.toggleFullscreen()
            else
                win.showSequence()
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

    UpdateDialog {
        app: win
        anchors.fill: parent
        visible: win.updatePromptOpen
    }
}
