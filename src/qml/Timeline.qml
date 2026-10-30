import QtQuick

// Trim timeline: tick labels, shaded outside range, handles, playhead.
Item {
    id: tl
    required property var app

    // The thumbnail strip underneath uses the same insets.
    readonly property real ticksH: 20
    readonly property real handleW: 10
    /// "00:00:00" in 11 px mono is ~55 px wide.
    readonly property real labelHalf: 28
    /// Minimum distance between tick positions; leaves room between labels.
    readonly property real labelGap: 90
    readonly property real grab: 12

    readonly property real trackX: handleW
    readonly property real trackW: width - 2 * handleW
    readonly property real trackY: ticksH
    readonly property real trackH: height - ticksH

    /// 0 none, 1 start handle, 2 end handle, 3 playhead
    property int drag: 0

    function xOf(sec) {
        const r = app.duration > 0 ? Math.min(Math.max(sec / app.duration, 0), 1) : 0
        return trackX + r * trackW
    }
    function timeAt(x) {
        return Math.min(Math.max((x - trackX) / trackW, 0), 1) * app.duration
    }
    function apply(t) {
        if (drag === 1)
            app.timelineTrim(Math.max(Math.min(t, app.trimEnd - 0.05), 0), app.trimEnd)
        else if (drag === 2)
            app.timelineTrim(app.trimStart, Math.max(t, app.trimStart + 0.05))
        else if (drag === 3)
            app.timelineSeek(t)
    }
    function nearHandle(x) {
        return Math.abs(x - xOf(app.trimStart)) <= grab || Math.abs(x - xOf(app.trimEnd)) <= grab
    }

    // The playhead is a separate item, so playback does not repaint the canvas.
    readonly property var paintKey: [app.duration, app.trimStart, app.trimEnd, width, height]
    onPaintKeyChanged: canvas.requestPaint()

    Canvas {
        id: canvas
        anchors.fill: parent
        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            const d = tl.app.duration
            if (d <= 0)
                return

            ctx.font = "11px '" + Theme.mono + "'"
            ctx.textBaseline = "top"
            ctx.fillStyle = Theme.tx3
            const step = Util.tickStep(d, tl.trackW, tl.labelGap)
            const right = tl.trackX + tl.trackW
            let prevEnd = -Infinity
            for (let s = 0; s <= d + 0.001; s += step) {
                // Labels at the edges are aligned flush instead of overflowing the track.
                const x = tl.xOf(s)
                let anchor = x, align = "center", left = x - tl.labelHalf
                if (x - tl.labelHalf < tl.trackX) {
                    anchor = tl.trackX; align = "left"; left = tl.trackX
                } else if (x + tl.labelHalf > right) {
                    anchor = right; align = "right"; left = right - 2 * tl.labelHalf
                }
                if (left < prevEnd + 8)
                    continue
                prevEnd = left + 2 * tl.labelHalf
                ctx.textAlign = align
                ctx.fillText(Util.formatTime(s, false), anchor, 2)
            }

            const sx = tl.xOf(tl.app.trimStart), ex = tl.xOf(tl.app.trimEnd)
            const y = tl.trackY, h = tl.trackH
            ctx.fillStyle = "rgba(0, 0, 0, 0.62)"
            ctx.fillRect(tl.trackX, y, sx - tl.trackX, h)
            ctx.fillRect(ex, y, right - ex, h)

            ctx.fillStyle = Theme.aText
            ctx.fillRect(sx, y, ex - sx, 2)
            ctx.fillRect(sx, y + h - 2, ex - sx, 2)
            for (const [x, isStart] of [[sx, true], [ex, false]]) {
                const hx = isStart ? x - tl.handleW : x
                ctx.fillStyle = Theme.aFill
                ctx.beginPath()
                ctx.roundedRect(hx, y, tl.handleW, h, 3, 3)
                ctx.fill()
                ctx.fillStyle = "white"
                ctx.fillRect(hx + tl.handleW / 2 - 1, y + h / 2 - 8, 2, 16)
            }
        }
    }

    Rectangle {
        x: tl.xOf(tl.app.position) - 1
        y: tl.trackY - 4
        width: 2
        height: tl.trackH + 8
        color: Theme.tx
        visible: tl.app.duration > 0
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: tl.drag === 1 || tl.drag === 2 || (tl.drag === 0 && tl.nearHandle(mouseX))
                     ? Qt.SizeHorCursor : tl.drag === 3 ? Qt.ClosedHandCursor : Qt.PointingHandCursor
        onPressed: m => {
            const sx = tl.xOf(tl.app.trimStart), ex = tl.xOf(tl.app.trimEnd)
            tl.drag = Math.abs(m.x - sx) <= tl.grab && m.x <= ex ? 1
                    : Math.abs(m.x - ex) <= tl.grab ? 2 : 3
            tl.app.clearFocus()
            tl.apply(tl.timeAt(m.x))
        }
        onPositionChanged: m => {
            if (tl.drag !== 0)
                tl.apply(tl.timeAt(m.x))
        }
        onReleased: {
            if (tl.drag !== 0) {
                tl.drag = 0
                tl.app.timelineRelease()
            }
        }
    }
}
