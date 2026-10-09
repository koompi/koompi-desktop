pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.modules.common
import "app-icon-plate.js" as Plate

// Every app icon in the shell goes through here: a squircle plate, the icon at 72 % of it, or, when the
// icon's theme declares a full-bleed body, the icon cut to the squircle. An icon that resolves to nothing
// gets the first letter of `label` on the plate.
Item {
    id: root

    property string iconName: ""
    property string label: ""
    property real size: 48

    readonly property string path: Plate.unresolved(root.iconName) ? "" : (root.iconName.startsWith("/") ? "file://" + root.iconName : Quickshell.iconPath(root.iconName, true))
    readonly property bool resolved: root.path.length > 0
    readonly property var box: root.resolved ? AppIconBodies.box(root.iconName) : null
    property bool maskFailed: false
    readonly property bool masked: root.box !== null && !root.maskFailed

    readonly property real tile: Plate.bucket(root.size)
    readonly property real margin: Plate.shadowMargin(root.tile)
    readonly property real ratio: root.size / root.tile
    readonly property bool dark: Appearance.m3colors.darkmode
    readonly property color fill: root.dark ? Appearance.m3colors.m3surfaceContainerHighest : "#ffffff"
    readonly property color edge: Qt.alpha(Appearance.m3colors.m3outlineVariant, 0.6)
    readonly property color shadow: Appearance.colors.colShadow
    readonly property string scheme: `${root.fill}|${root.edge}|${root.shadow}`

    readonly property string baseKey: `base:${root.scheme}:${root.tile}`
    readonly property string maskKey: `mask:${AppIconBodies.theme}:${root.iconName}:${root.tile}`
    readonly property string baseUrl: AppIconPlates.url(root.baseKey)
    readonly property string maskUrl: root.masked ? AppIconPlates.url(root.maskKey) : ""
    property string baseOwned: ""
    property string maskOwned: ""

    function refresh(): void {
        if (root.baseOwned !== root.baseKey && AppIconPlates.claim(root.baseKey, root.scheme)) root.baseOwned = root.baseKey;
        if (root.masked && root.maskOwned !== root.maskKey && AppIconPlates.claim(root.maskKey, "")) root.maskOwned = root.maskKey;
    }

    function release(): void {
        if (root.baseOwned) AppIconPlates.abandon(root.baseOwned);
        if (root.maskOwned) AppIconPlates.abandon(root.maskOwned);
        root.baseOwned = "";
        root.maskOwned = "";
    }

    onBaseKeyChanged: {
        if (root.baseOwned) AppIconPlates.abandon(root.baseOwned);
        root.baseOwned = "";
        root.refresh();
    }
    onMaskKeyChanged: {
        if (root.maskOwned) AppIconPlates.abandon(root.maskOwned);
        root.maskOwned = "";
        root.refresh();
    }
    Component.onCompleted: root.refresh()
    Component.onDestruction: root.release()

    Connections {
        target: AppIconPlates
        function onRevisionChanged() {
            root.refresh();
        }
    }

    implicitWidth: root.size
    implicitHeight: root.size

    Image {
        visible: root.baseUrl !== ""
        anchors.centerIn: parent
        width: (root.tile + root.margin * 2) * root.ratio
        height: width
        source: root.baseUrl
        smooth: true
        mipmap: true
    }

    Loader {
        active: root.baseUrl === ""
        anchors.centerIn: parent
        scale: root.ratio
        sourceComponent: AppIconPlateBase {
            side: root.tile
            margin: root.margin
            fill: root.fill
            edge: root.edge
            shadow: root.shadow
            grab: root.baseOwned === root.baseKey
            onRendered: result => {
                AppIconPlates.store(root.baseKey, result);
                root.baseOwned = "";
            }
        }
    }

    Image {
        visible: root.resolved && !root.masked
        anchors.centerIn: parent
        width: root.size * Plate.glyphRatio()
        height: width
        sourceSize: Qt.size(root.tile * Plate.glyphRatio() * 2, root.tile * Plate.glyphRatio() * 2)
        source: visible ? root.path : ""
        smooth: true
        mipmap: true
    }

    Image {
        visible: root.maskUrl !== ""
        anchors.centerIn: parent
        width: root.size
        height: width
        source: root.maskUrl
        smooth: true
        mipmap: true
    }

    Loader {
        active: root.masked && root.maskUrl === ""
        anchors.centerIn: parent
        scale: root.ratio
        sourceComponent: AppIconPlateMask {
            side: root.tile
            source: root.path
            lo: root.box?.lo ?? 0
            hi: root.box?.hi ?? 1
            grab: root.maskOwned === root.maskKey
            onRendered: result => {
                AppIconPlates.store(root.maskKey, result);
                root.maskOwned = "";
            }
            onFailed: {
                AppIconPlates.abandon(root.maskKey);
                root.maskOwned = "";
                root.maskFailed = true;
            }
        }
    }

    Text {
        visible: !root.resolved
        anchors.centerIn: parent
        text: Plate.letter(root.label || root.iconName)
        color: Appearance.m3colors.m3primary
        font.family: Appearance.font.family.main
        font.pixelSize: root.size * 0.42
        font.weight: Font.DemiBold
    }
}
