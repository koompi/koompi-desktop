import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

import qs.modules.koompi.controlCenter
import qs.modules.koompi.sidebarRight.calendar
import qs.modules.koompi.sidebarRight.glance
import qs.modules.koompi.sidebarRight.notifications
import qs.modules.koompi.sidebarRight.pomodoro
import qs.modules.koompi.sidebarRight.quickToggles.classicStyle
import qs.modules.koompi.sidebarRight.todo

Item {
    id: root
    property int sidebarWidth: Appearance.sizes.sidebarWidthRight
    property int sidebarPadding: Appearance.spacing.normal
    property string drawer: ""
    // Survives the slide-out so the drawer keeps its content while closing.
    property string drawerPage: ""
    property var returnTo: null
    property bool drawerWasOpen: false
    property alias head: headPage
    property alias body: bodyScroll
    property var brightnessMonitor: Brightness.getMonitorForScreen(root.QsWindow.window?.screen)
    readonly property var lists: ["wifi", "bluetooth", "sound", "power"]
    readonly property var titles: ({
            "calendar": Translation.tr("Calendar"),
            "todo": Translation.tr("To Do"),
            "timer": Translation.tr("Timer"),
            "display": Translation.tr("Display"),
            "nowPlaying": Translation.tr("Now Playing"),
            "battery": Translation.tr("Battery"),
            "edit": Translation.tr("Edit modules")
        })

    onDrawerChanged: {
        if (drawer.length > 0) {
            if (!drawerWasOpen)
                returnTo = root.Window.window?.activeFocusItem ?? null;
            drawerWasOpen = true;
            drawerPage = drawer;
            Qt.callLater(() => drawerView.backButton.forceActiveFocus(Qt.TabFocusReason));
        } else {
            drawerWasOpen = false;
            Qt.callLater(root.restoreFocus);
        }
    }

    function restoreFocus(): void {
        const target = root.returnTo;
        if (target && target.visible)
            target.forceActiveFocus(Qt.TabFocusReason);
        else
            headPage.focusFirst();
    }

    // Esc folds one thing at a time: the drawer, then an open list; false means nothing was open
    function back(): bool {
        if (root.drawer.length > 0) {
            root.drawer = "";
            return true;
        }
        return headPage.fold();
    }

    function showModule(name: string): void {
        if (root.lists.indexOf(name) >= 0) {
            root.drawer = "";
            headPage.expanded = name;
            bodyScroll.contentY = 0;
        } else {
            root.drawer = name;
        }
    }

    function reveal(item): void {
        if (!item || !bodyColumn.contains(bodyColumn.mapFromItem(item, 0, 0)))
            return;
        const top = item.mapToItem(bodyColumn, 0, 0).y;
        const bottom = top + item.height;
        if (top < bodyScroll.contentY)
            bodyScroll.contentY = Math.max(0, top - Appearance.spacing.normal);
        else if (bottom > bodyScroll.contentY + bodyScroll.height)
            bodyScroll.contentY = Math.min(bodyScroll.contentHeight - bodyScroll.height, bottom - bodyScroll.height + Appearance.spacing.normal);
    }

    Binding {
        target: CcMetrics
        property: "compact"
        value: (root.QsWindow.window?.screen?.height ?? 1000) < 1000
    }

    Connections {
        target: root.Window.window
        function onActiveFocusItemChanged() {
            root.reveal(root.Window.window.activeFocusItem);
        }
    }

    Connections {
        target: GlobalStates
        function onSidebarRightOpenChanged() {
            if (!GlobalStates.sidebarRightOpen) {
                root.drawer = "";
                headPage.expanded = "";
            } else {
                Qt.callLater(root.restoreFocus);
            }
        }
    }

    Keys.onPressed: event => {
        if ((event.key === Qt.Key_Down || event.key === Qt.Key_Up) && ["calendar", "todo", "timer"].indexOf(root.drawer) < 0) {
            const forward = event.key === Qt.Key_Down;
            let next = root.Window.window?.activeFocusItem?.nextItemInFocusChain(forward);
            for (let i = 0; next && next.tabOnly && i < 4; i++)
                next = next.nextItemInFocusChain(forward);
            next?.forceActiveFocus(Qt.TabFocusReason);
            event.accepted = true;
        }
    }

    Component.onCompleted: Qt.callLater(root.restoreFocus)

    implicitHeight: sidebarRightBackground.implicitHeight
    implicitWidth: sidebarRightBackground.implicitWidth

    StyledRectangularShadow {
        target: sidebarRightBackground
    }
    Rectangle {
        id: sidebarRightBackground

        anchors.fill: parent
        implicitHeight: parent.height - Appearance.sizes.hyprlandGapsOut * 2
        implicitWidth: sidebarWidth - Appearance.sizes.hyprlandGapsOut * 2
        color: Appearance.colors.colLayer0
        border.width: 1
        // The outline carries the keyboard. `Window.active` is this surface's own
        // focus, not `sidebarRightOpen`: the panel stays on screen when Search
        // opens over it and takes the keys.
        border.color: Window.active ? Appearance.colors.colPrimary : Appearance.colors.colLayer0Border
        radius: Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut + 1

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: sidebarPadding
            spacing: sidebarPadding

            SystemButtonRow {
                Layout.fillHeight: false
                Layout.fillWidth: true
                Layout.topMargin: Appearance.spacing.small
                Layout.bottomMargin: 0
            }

            StyledFlickable {
                id: bodyScroll
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: width
                contentHeight: bodyColumn.implicitHeight

                ColumnLayout {
                    id: bodyColumn
                    width: bodyScroll.width - (bodyScroll.ScrollBar.vertical?.visible ? 10 : 0)
                    spacing: sidebarPadding

                    CcMainPage {
                        id: headPage
                        Layout.fillWidth: true
                        brightnessMonitor: root.brightnessMonitor
                        onOpenPage: name => root.showModule(name)
                    }
                    NotificationCenter {
                        Layout.fillWidth: true
                    }
                    UpNextCard {
                        onClicked: root.drawer = "calendar"
                    }
                    WeatherCard {}
                    TodoCard {
                        onClicked: root.drawer = "todo"
                    }
                    TimerCard {
                        onClicked: root.drawer = "timer"
                    }
                }
            }
        }

        SidebarDrawer {
            id: drawerView
            shown: root.drawer.length > 0
            onDismissed: root.drawer = ""
            title: root.titles[root.drawerPage] ?? ""
            // Every page named, and an unknown one draws nothing. A default branch
            // here silently opened whichever page it named instead.
            sourceComponent: {
                switch (root.drawerPage) {
                case "calendar": return calendarPage;
                case "todo": return todoPage;
                case "timer": return timerPage;
                case "display": return displayPage;
                case "nowPlaying": return nowPlayingPage;
                case "battery": return batteryPage;
                case "edit": return editPage;
                }
                return null;
            }
        }
    }

    Component {
        id: calendarPage
        CalendarWidget {}
    }

    Component {
        id: todoPage
        TodoWidget {}
    }

    Component {
        id: timerPage
        PomodoroWidget {}
    }

    Component {
        id: displayPage
        CcPadded {
            CcDisplayPage {
                anchors.fill: parent
                brightnessMonitor: root.brightnessMonitor
            }
        }
    }

    Component {
        id: nowPlayingPage
        CcPadded {
            CcNowPlayingPage {
                anchors.fill: parent
            }
        }
    }

    Component {
        id: batteryPage
        CcPadded {
            CcBatteryPage {
                anchors.fill: parent
            }
        }
    }

    Component {
        id: editPage
        CcPadded {
            CcEditPage {
                anchors.fill: parent
            }
        }
    }

    component SystemButtonRow: Item {
        implicitHeight: Math.max(dateContainer.implicitHeight, systemButtonsRow.implicitHeight)

        Rectangle {
            id: dateContainer
            anchors {
                top: parent.top
                bottom: parent.bottom
                left: parent.left
            }
            color: Appearance.colors.colLayer1
            radius: height / 2
            implicitWidth: dateRow.implicitWidth + 24
            implicitHeight: dateRow.implicitHeight + 8

            Row {
                id: dateRow
                anchors.centerIn: parent
                spacing: Appearance.spacing.normal
                CustomIcon {
                    id: distroIcon
                    anchors.verticalCenter: parent.verticalCenter
                    width: 25
                    height: 25
                    source: SystemInfo.distroIcon
                    colorize: true
                    color: Appearance.colors.colOnLayer0
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, Math.max(0, systemButtonsRow.x - Appearance.spacing.small - 24 - distroIcon.width - dateRow.spacing))
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnLayer0
                    text: DateTime.fullDate
                }
            }
        }

        ButtonGroup {
            id: systemButtonsRow
            anchors {
                top: parent.top
                bottom: parent.bottom
                right: parent.right
            }
            color: Appearance.colors.colLayer1
            padding: Appearance.spacing.small

            QuickToggleButton {
                toggled: Persistent.states.sidebar.pinned
                buttonIcon: Persistent.states.sidebar.pinned ? "keep" : "keep_off"
                onClicked: Persistent.states.sidebar.pinned = !Persistent.states.sidebar.pinned
                StyledToolTip {
                    text: Translation.tr("Pin the panel open and tile windows beside it")
                }
            }
            QuickToggleButton {
                toggled: false
                buttonIcon: "settings"
                onClicked: {
                    GlobalStates.sidebarRightOpen = false;
                    Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/koompi-settings"]);
                }
                StyledToolTip {
                    text: Translation.tr("Settings")
                }
            }
            QuickToggleButton {
                toggled: false
                buttonIcon: "power_settings_new"
                onClicked: {
                    GlobalStates.sessionOpen = true;
                }
                StyledToolTip {
                    text: Translation.tr("Session")
                }
            }
        }
    }
}
