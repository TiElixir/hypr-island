import QtQuick
import QtQuick.Shapes
import "../core"

// Circular progress ring. Redraws only when `progress` changes.
Item {
    id: root

    property real progress: 0
    property real lineWidth: 2
    property color color: Theme.accent
    property color trackColor: Theme.track

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: "transparent"
            strokeColor: root.trackColor
            strokeWidth: root.lineWidth
            PathAngleArc {
                centerX: root.width / 2
                centerY: root.height / 2
                radiusX: (root.width - root.lineWidth) / 2
                radiusY: radiusX
                startAngle: 0
                sweepAngle: 360
            }
        }
        ShapePath {
            fillColor: "transparent"
            strokeColor: root.color
            strokeWidth: root.lineWidth
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: root.width / 2
                centerY: root.height / 2
                radiusX: (root.width - root.lineWidth) / 2
                radiusY: radiusX
                startAngle: -90
                sweepAngle: 360 * Math.max(0, Math.min(1, root.progress))
            }
        }
    }
}
