import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

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
    onDrawerChanged: if (drawer.length > 0) drawerPage = drawer

    Connections {
        target: GlobalStates
        function onSidebarRightOpenChanged() {
            if (!GlobalStates.sidebarRightOpen)
                root.drawer = "";
        }
    }

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
                id: body
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: width
                contentHeight: bodyColumn.implicitHeight

                ColumnLayout {
                    id: bodyColumn
                    width: body.width - (body.ScrollBar.vertical?.visible ? 10 : 0)
                    spacing: sidebarPadding

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
            shown: root.drawer.length > 0
            onDismissed: root.drawer = ""
            title: {
                if (root.drawerPage === "calendar") return Translation.tr("Calendar");
                if (root.drawerPage === "todo") return Translation.tr("To Do");
                if (root.drawerPage === "timer") return Translation.tr("Timer");
                return "";
            }
            // Every page named, and an unknown one draws nothing. A default branch
            // here silently opened whichever page it named instead.
            sourceComponent: {
                if (root.drawerPage === "calendar") return calendarPage;
                if (root.drawerPage === "todo") return todoPage;
                if (root.drawerPage === "timer") return timerPage;
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
