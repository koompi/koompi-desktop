import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell

FocusScope {
    id: root

    property string page: ""
    // survives the slide-out so the page keeps its content while it leaves
    property string shownPage: ""
    property real maxHeight: 700
    property var brightnessMonitor: Brightness.getMonitorForScreen(root.QsWindow.window?.screen)
    property var returnTo: null
    readonly property bool detailOpen: root.page.length > 0
    readonly property real slide: Appearance.reduceMotion ? 0 : 36
    property alias mainPage: mainPage
    property alias body: body

    signal closeRequested

    readonly property var titles: ({
            "wifi": Translation.tr("Wi-Fi"),
            "bluetooth": Translation.tr("Bluetooth"),
            "display": Translation.tr("Display"),
            "sound": Translation.tr("Sound"),
            "nowPlaying": Translation.tr("Now Playing"),
            "battery": Translation.tr("Battery"),
            "edit": Translation.tr("Edit modules")
        })

    function showPage(name: string): void {
        if (name.length > 0 && !root.detailOpen)
            root.returnTo = root.Window.window?.activeFocusItem ?? null;
        root.page = name;
    }

    function back(): void {
        root.page = "";
    }

    function pageComponent(name: string): Component {
        switch (name) {
        case "wifi": return wifiPage;
        case "bluetooth": return bluetoothPage;
        case "display": return displayPage;
        case "sound": return soundPage;
        case "nowPlaying": return nowPlayingPage;
        case "battery": return batteryPage;
        case "edit": return editPage;
        }
        return null;
    }

    function settleFocus(): void {
        if (root.detailOpen)
            backButton.forceActiveFocus(Qt.TabFocusReason);
        else
            root.restoreFocus();
    }

    function restoreFocus(): void {
        const target = root.returnTo;
        if (target && target.visible)
            target.forceActiveFocus(Qt.TabFocusReason);
        else
            mainPage.focusFirst();
    }

    onPageChanged: {
        if (root.page.length > 0)
            root.shownPage = root.page;
        // enabled and visible follow the page a beat later, and neither page takes focus before that
        Qt.callLater(root.settleFocus);
    }

    Component.onCompleted: mainPage.focusFirst()

    Binding {
        target: CcMetrics
        property: "compact"
        value: root.maxHeight < 760
    }

    Connections {
        target: GlobalStates
        function onControlCenterOpenChanged() {
            if (!GlobalStates.controlCenterOpen)
                root.page = "";
            else if (!root.detailOpen)
                mainPage.focusFirst();
        }
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) {
            if (root.detailOpen)
                root.back();
            else
                root.closeRequested();
            event.accepted = true;
        } else if (event.key === Qt.Key_Backspace && root.detailOpen) {
            root.back();
            event.accepted = true;
        } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Up) {
            // what a page's own controls leave unhandled: the arrows still walk the focus chain, as Tab does
            const from = root.Window.window?.activeFocusItem;
            from?.nextItemInFocusChain(event.key === Qt.Key_Down)?.forceActiveFocus(Qt.TabFocusReason);
            event.accepted = true;
        }
    }

    implicitWidth: 360
    implicitHeight: Math.min(root.maxHeight, Math.max(440, mainPage.implicitHeight + Appearance.spacing.normal * 2))

    Rectangle {
        anchors.fill: parent
        radius: Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut + 1
        color: Appearance.colors.colLayer0
        border.width: 1
        border.color: root.Window.active ? Appearance.colors.colPrimary : Appearance.colors.colLayer0Border
    }

    CcMainPage {
        id: mainPage
        anchors {
            fill: parent
            margins: Appearance.spacing.normal
        }
        enabled: !root.detailOpen
        x: root.detailOpen ? -root.slide : 0
        opacity: root.detailOpen ? 0 : 1
        visible: opacity > 0 || !root.detailOpen
        brightnessMonitor: root.brightnessMonitor
        onOpenPage: name => root.showPage(name)

        Behavior on x {
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
        }
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
    }

    ColumnLayout {
        id: detail
        anchors {
            fill: parent
            margins: Appearance.spacing.normal
        }
        enabled: root.detailOpen
        x: root.detailOpen ? 0 : root.slide
        opacity: root.detailOpen ? 1 : 0
        visible: opacity > 0 || root.detailOpen
        spacing: Appearance.spacing.normal

        Behavior on x {
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
        }
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Appearance.spacing.normal

            CcIconButton {
                id: backButton
                objectName: "cc-back"
                glyph: "arrow_back"
                label: Translation.tr("Back")
                onClicked: root.back()
            }
            StyledText {
                objectName: "cc-page-title"
                Layout.fillWidth: true
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.large
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer0
                text: root.titles[root.shownPage] ?? ""
            }
        }

        Loader {
            id: body
            objectName: "cc-page"
            Layout.fillWidth: true
            Layout.fillHeight: true
            sourceComponent: root.pageComponent(root.shownPage)
        }
    }

    Component {
        id: wifiPage
        CcWifiPage {}
    }
    Component {
        id: bluetoothPage
        CcBluetoothPage {}
    }
    Component {
        id: displayPage
        CcDisplayPage {
            brightnessMonitor: root.brightnessMonitor
        }
    }
    Component {
        id: soundPage
        CcSoundPage {}
    }
    Component {
        id: nowPlayingPage
        CcNowPlayingPage {}
    }
    Component {
        id: batteryPage
        CcBatteryPage {}
    }
    Component {
        id: editPage
        CcEditPage {}
    }
}
