import QtQuick

// What a song shows instead of a picture: a ring with rays pulsing outwards to the music,
// title and artist in its middle. Each ray shows the loudness a moment earlier than its
// neighbour, so the music runs around the ring as a wave; left and right mirror each other.
Item {
    id: vis
    /// Loudest sample per 1/20 s, 0..1.
    property var peaks: []
    property real position: 0
    property bool playing: false
    property string title
    property string artist

    readonly property int perSecond: 20
    readonly property int rays: 96
    /// How far back in time the rays reach, from the top round to the bottom.
    readonly property real memory: 1.6

    // mpv reports the position only now and then; in between it runs on by the clock.
    property real reportedAt: 0
    property real spin: 0
    /// Per ray, smoothed: rises at once, falls back slowly.
    property var levels: []

    function now() {
        return playing ? position + Math.min((Date.now() - reportedAt) / 1000, 0.25) : position
    }
    /// Loudness at `t`, between the buckets linearly.
    function loudness(t) {
        const f = t * perSecond, i = Math.floor(f)
        if (i < 0 || i >= peaks.length)
            return 0
        const a = peaks[i], b = i + 1 < peaks.length ? peaks[i + 1] : a
        return a + (b - a) * (f - i)
    }

    onPositionChanged: {
        reportedAt = Date.now()
        if (!playing)
            canvas.requestPaint()
    }
    onPeaksChanged: canvas.requestPaint()
    onWidthChanged: canvas.requestPaint()
    onHeightChanged: canvas.requestPaint()

    FrameAnimation {
        running: vis.visible && vis.playing
        onTriggered: {
            vis.spin += frameTime * 0.08
            canvas.requestPaint()
        }
    }

    Canvas {
        id: canvas
        anchors.fill: parent
        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            const half = vis.rays / 2
            const t = vis.now()
            const levels = vis.levels.length === half ? vis.levels : new Array(half).fill(0)
            let level = 0
            for (let k = 0; k < half; k++) {
                const target = vis.loudness(t - k / half * vis.memory)
                levels[k] = target > levels[k] ? target : levels[k] * 0.9 + target * 0.1
                level += levels[k] / half
            }
            vis.levels = levels

            const cx = width / 2, cy = height / 2
            const base = Math.min(width, height) * 0.24
            // The ring breathes with the loudness.
            const r = base * (1 + 0.08 * levels[0])
            const reach = base * 0.75

            ctx.lineCap = "round"
            ctx.strokeStyle = Theme.aText
            ctx.globalAlpha = 0.18 + 0.25 * level
            ctx.lineWidth = 2
            ctx.beginPath()
            ctx.arc(cx, cy, r - 6, 0, 2 * Math.PI)
            ctx.stroke()

            for (let i = 0; i < vis.rays; i++) {
                const k = i < half ? i : vis.rays - 1 - i
                const v = levels[k]
                const angle = vis.spin + i / vis.rays * 2 * Math.PI - Math.PI / 2
                const len = 4 + v * reach
                const cos = Math.cos(angle), sin = Math.sin(angle)
                const x0 = cx + cos * r, y0 = cy + sin * r
                const x1 = cx + cos * (r + len), y1 = cy + sin * (r + len)
                // A wide faint stroke under a thin one makes the glow.
                ctx.globalAlpha = 0.12 + 0.2 * v
                ctx.lineWidth = 9
                ctx.beginPath()
                ctx.moveTo(x0, y0)
                ctx.lineTo(x1, y1)
                ctx.stroke()
                ctx.globalAlpha = 0.55 + 0.45 * v
                ctx.lineWidth = 3.5
                ctx.beginPath()
                ctx.moveTo(x0, y0)
                ctx.lineTo(x1, y1)
                ctx.stroke()
            }
        }
    }

    Column {
        anchors.centerIn: parent
        width: Math.min(vis.width, vis.height) * 0.4
        spacing: 6
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: vis.title
            elide: Text.ElideRight
            maximumLineCount: 2
            wrapMode: Text.Wrap
            color: Theme.tx
            font.pixelSize: 20
            font.weight: Font.DemiBold
        }
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            visible: text !== ""
            text: vis.artist
            elide: Text.ElideRight
            color: Theme.tx2
            font.pixelSize: 14
        }
    }
}
