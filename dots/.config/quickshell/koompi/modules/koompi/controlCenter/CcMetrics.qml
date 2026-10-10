pragma Singleton
import QtQuick
import Quickshell

// a short screen gets tighter rows so the whole list still fits under the bar
Singleton {
    property bool compact: false
    readonly property real rowHeight: compact ? 46 : 54
    readonly property real sliderHeight: compact ? 76 : 82
    readonly property real plate: compact ? 32 : 36
}
