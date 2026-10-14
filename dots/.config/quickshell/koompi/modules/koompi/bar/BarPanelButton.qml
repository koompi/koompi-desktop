import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.widgets

// A bar button that opens one panel: its own hit area, drawn toggled while the panel is open.
RippleButton {
    id: root
    // the colours of the surface it is drawn on: the bar's glass may be the other tone (BarScheme)
    readonly property BarScheme barScheme: root.QsWindow.window?.barScheme ?? ownBarScheme
    BarScheme {
        id: ownBarScheme
    }

    property string tooltip: ""
    property bool vertical: false
    property color colText: toggled ? Appearance.m3colors.m3onSecondaryContainer : root.barScheme.fg

    Layout.alignment: root.vertical ? Qt.AlignHCenter : Qt.AlignVCenter
    implicitWidth: root.vertical ? Appearance.sizes.baseVerticalBarWidth - Appearance.spacing.small * 2 : contentItem.implicitWidth + Appearance.spacing.small * 2
    implicitHeight: root.vertical ? contentItem.implicitHeight + Appearance.spacing.small * 2 : Appearance.sizes.baseBarHeight - Appearance.spacing.small * 2
    padding: 0
    buttonRadius: Appearance.rounding.full
    colBackground: "transparent"
    colBackgroundHover: root.barScheme.hover
    colRipple: root.barScheme.pressed
    colBackgroundToggled: Appearance.colors.colSecondaryContainer
    colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
    colRippleToggled: Appearance.colors.colSecondaryContainerActive

    PopupToolTip {
        extraVisibleCondition: root.tooltip !== "" && root.hovered
        anchorEdges: (!Config.options.bar.bottom && !Config.options.bar.vertical) ? Edges.Bottom : Edges.Top
        text: root.tooltip
    }
}
