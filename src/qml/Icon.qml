import QtQuick
import QtQuick.Shapes

// Line icons on a 24 × 24 grid: `fill` parts are solid, `stroke` parts drawn at 1.8.
Item {
    id: root
    property string name
    property real size: 16
    property color color: Theme.tx

    readonly property var paths: ({
        play: { fill: "M6 4 L20 12 L6 20 Z" },
        pause: { fill: "M6 4 h4 v16 h-4 Z M14 4 h4 v16 h-4 Z" },
        skipBack: { fill: "M19 20 L9 12 L19 4 Z", stroke: "M5 4 L5 20" },
        skipFwd: { fill: "M5 4 L15 12 L5 20 Z", stroke: "M19 4 L19 20" },
        frameBack: { stroke: "M6 5 L6 19 M17 6 L11 12 L17 18" },
        frameFwd: { stroke: "M18 5 L18 19 M7 6 L13 12 L7 18" },
        volume: { fill: "M11 5 L6 9 L2 9 L2 15 L6 15 L11 19 Z",
                  stroke: "M15.54 8.46 a5 5 0 0 1 0 7.07 M19.07 4.93 a10 10 0 0 1 0 14.14" },
        mute: { fill: "M11 5 L6 9 L2 9 L2 15 L6 15 L11 19 Z", stroke: "M23 9 L17 15 M17 9 L23 15" },
        fullscreen: { stroke: "M4 9 V4 h5 M20 9 V4 h-5 M4 15 v5 h5 M20 15 v5 h-5" },
        folder: { stroke: "M3 7 a2 2 0 0 1 2 -2 h4 l2 2 h8 a2 2 0 0 1 2 2 v9 a2 2 0 0 1 -2 2 H5 a2 2 0 0 1 -2 -2 V7 Z" },
        scissors: { stroke: "M3 6 a3 3 0 1 0 6 0 a3 3 0 1 0 -6 0 M3 18 a3 3 0 1 0 6 0 a3 3 0 1 0 -6 0 M20 4 L8.12 15.88 M14.47 14.48 L20 20 M8.12 8.12 L12 12" },
        upload: { stroke: "M21 15 v4 a2 2 0 0 1 -2 2 H5 a2 2 0 0 1 -2 -2 v-4 M17 8 L12 3 L7 8 M12 3 L12 15" },
        info: { fill: "M11.5 8 a0.5 0.5 0 1 0 1 0 a0.5 0.5 0 1 0 -1 0",
                stroke: "M3 12 a9 9 0 1 0 18 0 a9 9 0 1 0 -18 0 M12 11 L12 17 M11.5 8 a0.5 0.5 0 1 0 1 0 a0.5 0.5 0 1 0 -1 0" },
        trash: { stroke: "M3 6 h18 M8 6 V4 h8 v2 M6 6 l1 15 h10 l1 -15 M10 11 v6 M14 11 v6" },
        file: { stroke: "M14 2 H6 a2 2 0 0 0 -2 2 v16 a2 2 0 0 0 2 2 h12 a2 2 0 0 0 2 -2 V8 Z M14 2 L14 8 L20 8" },
        frame: { stroke: "M4 5 h16 a1 1 0 0 1 1 1 v12 a1 1 0 0 1 -1 1 H4 a1 1 0 0 1 -1 -1 V6 a1 1 0 0 1 1 -1 Z" },
        clock: { stroke: "M3 12 a9 9 0 1 0 18 0 a9 9 0 1 0 -18 0 M12 7 L12 12 L16 14" },
        drive: { stroke: "M3 5 a9 3 0 1 0 18 0 a9 3 0 1 0 -18 0 M3 5 v6 c0 1.66 4.03 3 9 3 s9 -1.34 9 -3 V5 M3 11 v6 c0 1.66 4.03 3 9 3 s9 -1.34 9 -3 v-6" },
        close: { stroke: "M18 6 L6 18 M6 6 L18 18" },
        camera: { stroke: "M23 19 a2 2 0 0 1 -2 2 H3 a2 2 0 0 1 -2 -2 V8 a2 2 0 0 1 2 -2 h4 l2 -3 h6 l2 3 h4 a2 2 0 0 1 2 2 Z M8 13 a4 4 0 1 0 8 0 a4 4 0 1 0 -8 0" }
    })
    readonly property var icon: paths[name] ?? {}

    implicitWidth: size
    implicitHeight: size

    Shape {
        width: 24
        height: 24
        scale: root.size / 24
        transformOrigin: Item.TopLeft
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: -1
            strokeColor: "transparent"
            fillColor: root.icon.fill ? root.color : "transparent"
            PathSvg { path: root.icon.fill ?? "" }
        }
        ShapePath {
            strokeWidth: root.icon.stroke ? 1.8 : -1
            strokeColor: root.icon.stroke ? root.color : "transparent"
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: root.icon.stroke ?? "" }
        }
    }
}
