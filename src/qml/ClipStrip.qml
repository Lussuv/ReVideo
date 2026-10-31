import QtQuick

// Clips joined on export, each as wide as its trimmed length. Files from the file
// manager drop in between, the "+" on a hovered tile's edges adds before or after it,
// tiles drag to a new place, a click opens the clip for trimming. Underneath, on the
// same time scale, the music tracks: pieces of songs, dragged to set their timing, with a
// volume line each. The razor tool (C) cuts clips and pieces where they are clicked.
Item {
    id: strip
    required property var app

    readonly property real gap: 6
    readonly property real clipH: 64
    readonly property real laneH: 56
    readonly property real emptyH: 30
    readonly property real laneGap: 8
    readonly property real toolsW: 34
    property bool musicDropHover: false
    /// Index of the tile being dragged; -1 none.
    property int dragFrom: -1

    implicitHeight: laneY(app.musicTracks.length) + emptyH

    function laneY(track) {
        return clipH + laneGap + track * (laneH + laneGap)
    }

    /// Tile widths strictly proportional to the trimmed length. If that would make the
    /// shortest clip narrower than 6 % of the strip, all tiles grow alike and the strip scrolls.
    readonly property var widths: {
        const lengths = app.clipLengths
        const avail = flick.width - 2 * pad - gap * Math.max(lengths.length - 1, 0)
        const min = 0.06 * avail
        const known = lengths.filter(l => l > 0)
        if (known.length === 0)
            return lengths.map(() => min)
        const total = known.reduce((a, b) => a + b, 0)
        // Clips still being read count as minimum width.
        const perSec = Math.max((avail - min * (lengths.length - known.length)) / total, min / Math.min(...known))
        return lengths.map(l => l > 0 ? l * perSec : min)
    }
    /// Room at both ends for the half of an edge "+" that sticks out of the tile.
    readonly property real pad: 11

    /// Position on the joined timeline → x in row coordinates, over the tiles (gaps included).
    function xAt(t) {
        let acc = 0
        for (let i = 0; i < tiles.count; i++) {
            const tile = tiles.itemAt(i)
            const l = app.clipLengths[i] ?? 0
            if (!tile)
                return 0
            if (t <= acc + l || i === tiles.count - 1)
                return tile.x + (l > 0 ? (t - acc) / l * tile.width : 0)
            acc += l
        }
        return 0
    }
    /// Inverse of xAt().
    function timeAt(x) {
        let acc = 0
        for (let i = 0; i < tiles.count; i++) {
            const tile = tiles.itemAt(i)
            const l = app.clipLengths[i] ?? 0
            if (!tile)
                return 0
            if (x <= tile.x + tile.width || i === tiles.count - 1)
                return acc + (tile.width > 0 ? (x - tile.x) / tile.width * l : 0)
            acc += l
        }
        return 0
    }

    /// Index the moving tiles `from` .. `from + n - 1` (the dragged one or the placeholders)
    /// take for `x`: one past every other tile whose middle lies left of it.
    function slotAt(x, from, n) {
        let slot = 0
        for (let i = 0; i < tiles.count; i++) {
            const t = tiles.itemAt(i)
            if ((i < from || i >= from + n) && t && t.x + t.width / 2 < x)
                slot++
        }
        return slot
    }

    /// What the razor would cut at strip position (`x`, `y`): {x, y, h} of the cut line in
    /// row coordinates plus the cut itself, or null.
    function cutAt(x, y) {
        const rx = x - flick.x + flick.contentX - row.x
        if (y < clipH) {
            for (let i = 0; i < tiles.count; i++) {
                const tile = tiles.itemAt(i)
                const c = app.clips.get(i)
                if (!tile || rx < tile.x || rx > tile.x + tile.width || !c.ready || c.end <= c.start)
                    continue
                const t = c.start + (rx - tile.x) / tile.width * (c.end - c.start)
                return { x: rx, y: 0, h: clipH, clip: i, t: t }
            }
            return null
        }
        const track = Math.floor((y - clipH - laneGap) / (laneH + laneGap))
        const pieces = app.musicTracks[track]
        if (!pieces || y < laneY(track))
            return null
        const t = timeAt(rx)
        for (let i = 0; i < pieces.length; i++) {
            const p = pieces[i]
            if (p.length > 0 && t > p.offset && t < p.offset + p.length)
                return { x: rx, y: laneY(track), h: laneH, track: track, piece: i, t: t }
        }
        return null
    }

    // Select and razor, as in editing programs.
    Column {
        id: tools
        x: 0
        y: 0
        width: strip.toolsW
        spacing: 2

        Btn {
            variant: "tab"
            active: !strip.app.cutMode
            iconName: "pointer"
            padding: 7
            tip: "Auswählen (V)"
            onClicked: strip.app.cutMode = false
        }
        Btn {
            variant: "tab"
            active: strip.app.cutMode
            iconName: "scissors"
            padding: 7
            tip: "Schneiden (C)"
            onClicked: strip.app.cutMode = !strip.app.cutMode
        }
        Btn {
            variant: "tab"
            active: strip.app.sequenceMode
            iconName: "film"
            padding: 7
            tip: "Ganze Timeline abspielen (Esc)"
            onClicked: strip.app.showSequence()
        }
    }

    Flickable {
        id: flick
        anchors.left: tools.right
        anchors.leftMargin: 6
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        contentWidth: row.width + 2 * strip.pad
        contentHeight: height
        interactive: false
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        // Wheel and touchpad scroll sideways. The Flickable itself is not interactive: it
        // takes the wheel without moving. This area lies beneath everything, so it gets
        // only what nothing else wants and leaves the cursors alone. A click into the free
        // space of the clip row deselects the clips: the whole timeline plays.
        MouseArea {
            width: flick.contentWidth
            height: flick.height
            onClicked: m => {
                if (m.y < strip.clipH)
                    strip.app.showSequence()
            }
            onWheel: w => {
                // A wheel notch (120) scrolls 55 % of the visible strip, the same on every
                // screen; touchpads follow the fingers. Wayland also gives wheels a small
                // pixel delta, so only the device type decides.
                const delta = w.device.type === InputDevice.TouchPad
                              ? w.pixelDelta.x || w.pixelDelta.y
                              : (w.angleDelta.y || w.angleDelta.x) / 120 * flick.width * 0.55
                flick.contentX = Math.min(Math.max(flick.contentX - delta, 0),
                                          Math.max(flick.contentWidth - flick.width, 0))
            }
        }

        Row {
            id: row
            x: strip.pad
            height: strip.clipH
            spacing: strip.gap

            Repeater {
                id: tiles
                model: strip.app.clips

                Rectangle {
                    id: tile
                    required property int index
                    required property string path
                    required property string name
                    required property bool ready
                    required property real start
                    required property real end
                    required property string thumb
                    required property bool hasAudio
                    required property bool muted
                    readonly property bool current: index === strip.app.currentClip
                    readonly property real length: Math.max(end - start, 0)
                    readonly property bool placeholder: path === ""
                    readonly property bool dragged: strip.dragFrom === index

                    width: strip.widths[index] ?? 0
                    height: row.height
                    radius: Theme.r1
                    color: hover.hovered && !placeholder ? Theme.sf3 : Theme.sf2
                    // On the whole timeline the clip that plays is marked more quietly.
                    readonly property bool playing: strip.app.sequenceMode && index === strip.app.timelineIndex
                    border.color: current && !dragged ? Theme.aText : playing ? Theme.tx2 : Theme.ln
                    border.width: current && !dragged || playing ? 2 : 1
                    opacity: dragged || placeholder ? 0.4 : 1
                    // The edge "+" overlaps the neighbour tile.
                    z: showAdd ? 1 : 0
                    readonly property bool showAdd: (hover.hovered || addBefore.hovered || addAfter.hovered)
                                                    && strip.dragFrom < 0 && !placeholder

                    HoverHandler { id: hover }

                    Image {
                        id: thumbImg
                        visible: !tile.placeholder
                        x: tile.border.width
                        y: tile.border.width
                        height: parent.height - 2 * y
                        width: Math.min(height * 16 / 9, parent.width / 2)
                        source: tile.thumb
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        clip: true
                    }
                    Column {
                        visible: !tile.placeholder
                        anchors.left: thumbImg.right
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 4
                        Text {
                            width: parent.width
                            text: tile.name
                            elide: Text.ElideMiddle
                            color: Theme.tx
                            font.pixelSize: 13
                        }
                        Text {
                            width: parent.width
                            elide: Text.ElideRight
                            text: tile.ready || tile.length > 0 ? Util.formatTime(tile.length, true) : "wird gelesen …"
                            color: Theme.tx3
                            font.family: Theme.mono
                            font.pixelSize: 12
                        }
                    }

                    MouseArea {
                        property real pressX
                        anchors.fill: parent
                        enabled: !tile.placeholder
                        preventStealing: true
                        cursorShape: strip.dragFrom >= 0 ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                        onPressed: m => {
                            pressX = m.x
                            strip.app.clearFocus()
                        }
                        onPositionChanged: m => {
                            if (strip.dragFrom < 0 && Math.abs(m.x - pressX) > 6)
                                strip.dragFrom = tile.index
                            if (strip.dragFrom < 0)
                                return
                            // The tile itself moves; the Repeater keeps it, so the drag goes on.
                            const slot = strip.slotAt(tile.x + m.x, strip.dragFrom, 1)
                            if (slot !== strip.dragFrom) {
                                strip.app.moveClip(strip.dragFrom, slot)
                                strip.dragFrom = slot
                            }
                        }
                        onReleased: {
                            // A second click on the selected clip deselects it: the whole timeline plays.
                            if (strip.dragFrom < 0 && tile.index === strip.app.currentClip)
                                strip.app.showSequence()
                            else if (strip.dragFrom < 0)
                                strip.app.selectClip(tile.index)
                            strip.dragFrom = -1
                        }
                        onCanceled: strip.dragFrom = -1
                    }

                    Row {
                        readonly property bool shown: hover.hovered && strip.dragFrom < 0 && !tile.placeholder
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 4
                        spacing: 2

                        // A muted clip shows it all the time.
                        Btn {
                            visible: tile.hasAudio && (parent.shown || tile.muted)
                            variant: "ghost"
                            iconName: tile.muted ? "mute" : "volume"
                            iconColor: tile.muted ? Theme.err : fg
                            iconSize: 14
                            padding: 4
                            tip: tile.muted ? "Ton einschalten" : "Clip stumm schalten"
                            onClicked: strip.app.toggleClipMute(tile.index)
                        }
                        Btn {
                            visible: parent.shown && tiles.count > 1
                            variant: "ghost"
                            iconName: "close"
                            iconSize: 14
                            padding: 4
                            tip: "Clip entfernen"
                            onClicked: strip.app.removeClip(tile.index)
                        }
                    }
                    EdgeAdd {
                        id: addBefore
                        x: -width / 2
                        visible: tile.showAdd
                        tip: "Clip davor einfügen"
                        onClicked: strip.app.pickClips(tile.index)
                    }
                    EdgeAdd {
                        id: addAfter
                        x: tile.width - width / 2
                        visible: tile.showAdd
                        tip: "Clip dahinter einfügen"
                        onClicked: strip.app.pickClips(tile.index + 1)
                    }
                }
            }
        }

        Repeater {
            model: strip.app.musicTracks.length

            Rectangle {
                id: lane
                required property int index
                readonly property var pieces: strip.app.musicTracks[index] ?? []
                x: row.x
                y: strip.laneY(index)
                width: row.width
                height: strip.laneH
                radius: Theme.r1
                color: Theme.bg2
                border.color: Theme.lnSoft
                // Music before the first or after the last clip is cut off.
                clip: true

                Repeater {
                    model: lane.pieces.length
                    // One piece of a song.
                    Rectangle {
                        id: piece
                        required property int index
                        readonly property int track: lane.index
                        readonly property var p: lane.pieces[index] ?? ({})
                        readonly property bool ready: (p.length ?? 0) > 0
                        // The part on screen, in the piece's coordinates; the song can be many screens wide.
                        readonly property real visLeft: Math.max(flick.contentX - row.x - x, 0)
                        readonly property real visRight: Math.min(flick.contentX - row.x + flick.width - x, width)

                        // Ends at the lane's edges with its own border; what lies beyond the clips is cut.
                        x: ready ? Math.max(strip.xAt(p.offset), 0) : 0
                        width: ready ? Math.max(Math.min(strip.xAt(p.offset + p.length), lane.width) - x, 0) : lane.width
                        height: lane.height
                        radius: Theme.r1
                        color: Qt.alpha(Theme.aFill, pieceArea.mode === 1 ? 0.5 : 0.32)
                        border.color: Qt.alpha(Theme.aText, 0.7)

                        readonly property real mid: height / 2
                        readonly property real amp: height / 2 - 4
                        readonly property real lineY: mid - (p.volume ?? 1) * amp

                        Text {
                            visible: !piece.ready
                            x: 12
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Musik wird gelesen …"
                            color: Theme.tx2
                            font.pixelSize: 12
                        }

                        Canvas {
                            id: wave
                            readonly property var paintKey: [x, width, height, piece.p, row.width, strip.app.clipLengths]
                            x: piece.visLeft
                            width: Math.max(piece.visRight - piece.visLeft, 0)
                            height: parent.height
                            visible: piece.ready
                            onPaintKeyChanged: requestPaint()
                            onPaint: {
                                const ctx = getContext("2d")
                                ctx.reset()
                                const p = piece.p, peaks = p.peaks
                                if (!peaks || peaks.length === 0)
                                    return
                                ctx.fillStyle = Theme.aText
                                // Toned down, so that the volume line stands out.
                                ctx.globalAlpha = 0.6
                                // 2 px bars with 1 px gaps; each takes the loudest bucket under it.
                                for (let px = 0; px < width; px += 3) {
                                    const lx = piece.x + x + px
                                    const t0 = strip.timeAt(lx) - p.offset, t1 = strip.timeAt(lx + 3) - p.offset
                                    if (t1 <= 0 || t0 >= p.length)
                                        continue
                                    let peak = 0
                                    const last = Math.min(Math.ceil((p.start + t1) * 20), peaks.length)
                                    for (let i = Math.max(Math.floor((p.start + t0) * 20), 0); i < last; i++)
                                        peak = Math.max(peak, peaks[i])
                                    const h = Math.max(peak * p.volume * piece.amp, 0.5)
                                    ctx.fillRect(px, piece.mid - h, 2, 2 * h)
                                }
                            }
                        }

                        // Volume line: the waveform's top at the current volume, dragged up and down.
                        Rectangle {
                            id: volumeLine
                            readonly property bool hot: pieceArea.onLine || pieceArea.mode === 2
                            visible: piece.ready
                            x: piece.visLeft
                            width: Math.max(piece.visRight - piece.visLeft, 0)
                            y: piece.lineY - height / 2
                            height: hot ? 3 : 2
                            color: "white"
                            opacity: hot ? 1 : 0.85
                        }
                        // Grip and level at the start of the visible part.
                        Rectangle {
                            id: volumeGrip
                            visible: piece.ready && piece.visRight - piece.visLeft > 60
                            x: piece.visLeft + 8
                            y: piece.lineY - height / 2
                            width: volumeLine.hot ? 12 : 10
                            height: width
                            radius: width / 2
                            color: "white"
                            border.color: Theme.aFill
                            border.width: 2
                        }
                        Rectangle {
                            visible: volumeGrip.visible
                            x: volumeGrip.x + volumeGrip.width + 6
                            y: Math.min(Math.max(piece.lineY - height / 2, 2), piece.height - height - 2)
                            width: level.implicitWidth + 10
                            height: level.implicitHeight + 4
                            radius: 4
                            color: Qt.rgba(0, 0, 0, 0.6)
                            Text {
                                id: level
                                anchors.centerIn: parent
                                text: Math.round((piece.p.volume ?? 1) * 100) + " %"
                                color: volumeLine.hot ? Theme.tx : Theme.tx2
                                font.family: Theme.mono
                                font.pixelSize: 11
                            }
                        }

                        MouseArea {
                            id: pieceArea
                            /// 0 none, 1 moving the piece, 2 setting the volume
                            property int mode: 0
                            property real pressTime
                            property real startOffset
                            readonly property bool onLine: containsMouse && mode === 0 && Math.abs(mouseY - piece.lineY) <= 6
                            anchors.fill: parent
                            enabled: piece.ready
                            hoverEnabled: true
                            preventStealing: true
                            cursorShape: mode === 2 || onLine ? Qt.SizeVerCursor : mode === 1 ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                            onPressed: m => {
                                strip.app.clearFocus()
                                mode = Math.abs(m.y - piece.lineY) <= 6 ? 2 : 1
                                startOffset = piece.p.offset
                                pressTime = strip.timeAt(mapToItem(lane, m.x, 0).x)
                            }
                            onPositionChanged: m => {
                                if (mode === 2)
                                    strip.app.setPieceVolume(piece.track, piece.index,
                                                             Math.min(Math.max((piece.mid - m.y) / piece.amp, 0), 1))
                                else if (mode === 1)
                                    strip.app.movePiece(piece.track, piece.index,
                                                        startOffset + strip.timeAt(mapToItem(lane, m.x, 0).x) - pressTime)
                            }
                            onReleased: mode = 0
                            onCanceled: mode = 0
                        }

                        Btn {
                            x: piece.visRight - width - 4
                            y: 4
                            visible: (pieceArea.containsMouse || hovered) && pieceArea.mode === 0 && !volumeLine.hot
                            variant: "ghost"
                            iconName: "close"
                            iconSize: 12
                            padding: 3
                            tip: "Musik entfernen"
                            onClicked: strip.app.removePiece(piece.track, piece.index)
                        }
                    }
                }
            }
        }

        // Always one more: a click or a dropped song makes a new track.
        Rectangle {
            id: emptyLane
            x: row.x
            y: strip.laneY(strip.app.musicTracks.length)
            width: row.width
            height: strip.emptyH
            radius: Theme.r1
            color: emptyHover.hovered || strip.musicDropHover ? Theme.sf : Theme.bg2
            border.color: strip.musicDropHover ? Theme.aText : Theme.lnSoft

            HoverHandler {
                id: emptyHover
                cursorShape: Qt.PointingHandCursor
            }
            TapHandler { onTapped: strip.app.pickMusic() }
            Row {
                // Centered in the visible part while the strip scrolls.
                x: flick.contentX - emptyLane.x + (flick.width - width) / 2
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: "music"
                    size: 14
                    color: emptyHover.hovered ? Theme.tx : Theme.tx3
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: strip.app.hasMusic ? "Weitere Musik" : "Musik hinzufügen"
                    color: emptyHover.hovered ? Theme.tx : Theme.tx3
                    font.pixelSize: 12
                }
            }
        }

        // Playhead on the joined timeline, across clips and music tracks.
        Rectangle {
            visible: strip.app.timelineIndex >= 0
            x: row.x + strip.xAt(strip.app.timelinePosition) - 1
            y: 0
            width: 2
            height: strip.laneY(strip.app.musicTracks.length) - strip.laneGap
            color: Theme.tx
        }

        // Where the razor would cut.
        Rectangle {
            visible: razor.target !== null
            x: row.x + (razor.target?.x ?? 0) - 1
            y: razor.target?.y ?? 0
            width: 2
            height: razor.target?.h ?? 0
            color: Theme.err
        }
    }

    // Razor tool: covers clips and music while it is on.
    MouseArea {
        id: razor
        property var target: null
        anchors.fill: flick
        visible: strip.app.cutMode
        hoverEnabled: true
        cursorShape: Qt.CrossCursor
        onPositionChanged: m => target = strip.cutAt(m.x + flick.x, m.y)
        onExited: target = null
        onClicked: m => {
            const cut = strip.cutAt(m.x + flick.x, m.y)
            if (cut && cut.clip !== undefined)
                strip.app.cutClip(cut.clip, cut.t)
            else if (cut)
                strip.app.cutPiece(cut.track, cut.piece, cut.t)
            target = strip.cutAt(m.x + flick.x, m.y)
        }
    }

    // Video files from the file manager; a placeholder tile per video shows where they go.
    DropArea {
        id: clipDrop
        function videos(d) {
            const paths = []
            for (let i = 0; i < d.urls.length; i++) {
                const path = Util.urlToPath(d.urls[i])
                if (strip.app.isVideo(path))
                    paths.push(path)
            }
            return paths
        }
        function place(d) {
            strip.app.showPlaceholder(strip.slotAt(d.x + flick.contentX - row.x, strip.app.placeholderIndex,
                                                   strip.app.placeholderCount), videos(d).length)
        }
        anchors.left: flick.left
        anchors.right: flick.right
        anchors.top: flick.top
        height: strip.clipH
        onEntered: d => {
            d.accepted = clipDrop.videos(d).length > 0
            if (d.accepted)
                clipDrop.place(d)
        }
        onPositionChanged: d => clipDrop.place(d)
        onExited: strip.app.hidePlaceholder()
        onDropped: d => {
            const paths = clipDrop.videos(d)
            const at = strip.app.placeholderIndex
            strip.app.hidePlaceholder()
            strip.app.addClips(paths, at >= 0 ? at : tiles.count)
            // Copy, never move: a file manager would otherwise remove the source.
            d.accept(Qt.CopyAction)
        }
    }

    // Songs from the file manager, anywhere on the music tracks: each gets a new track.
    DropArea {
        id: musicDrop
        function songs(d) {
            const paths = []
            for (let i = 0; i < d.urls.length; i++) {
                const path = Util.urlToPath(d.urls[i])
                if (strip.app.isAudio(path))
                    paths.push(path)
            }
            return paths
        }
        anchors.left: flick.left
        anchors.right: flick.right
        anchors.bottom: flick.bottom
        anchors.top: flick.top
        anchors.topMargin: strip.clipH
        onEntered: d => {
            d.accepted = musicDrop.songs(d).length > 0
            strip.musicDropHover = d.accepted
        }
        onExited: strip.musicDropHover = false
        onDropped: d => {
            strip.musicDropHover = false
            strip.app.addMusic(musicDrop.songs(d))
            d.accept(Qt.CopyAction)
        }
    }

    component EdgeAdd: Btn {
        anchors.verticalCenter: parent.verticalCenter
        variant: "secondary"
        iconName: "plus"
        iconSize: 14
        padding: 3
    }
}
