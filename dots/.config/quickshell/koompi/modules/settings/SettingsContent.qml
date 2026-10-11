import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// The settings page: navigation rail and the current page. The standalone settings.qml and the
// resident window in the shell both host it; each decides what "close" means.
Item {
    id: root
    property real contentPadding: 8
    property var pages: SettingsPages.list
    property string initialPage: ""
    property int currentPage: root.pageIndex(root.initialPage)
    signal closeRequested()

    // pages are named by their component filename, so page names need no separate registry
    function pageIndex(name: string): int {
        const requested = (name ?? "").toLowerCase();
        if (requested.length === 0) return 0;
        const idx = root.pages.findIndex(p => p.component.toLowerCase().includes(requested));
        return idx >= 0 ? idx : 0;
    }

    function pagePath(index: int): string {
        return Quickshell.shellPath(root.pages[index].component);
    }

    function showPage(name: string): void {
        root.currentPage = root.pageIndex(name);
    }

    // window shortcuts, not Keys on the layout: those stop once focus moves into a page, and
    // Ctrl+Shift+Tab carries Shift, so a Control-only modifier test never matched it
    Shortcut {
        sequence: "Ctrl+PgDown"
        onActivated: root.currentPage = Math.min(root.currentPage + 1, root.pages.length - 1)
    }
    Shortcut {
        sequence: "Ctrl+PgUp"
        onActivated: root.currentPage = Math.max(root.currentPage - 1, 0)
    }
    Shortcut {
        sequences: [StandardKey.NextChild]
        onActivated: root.currentPage = (root.currentPage + 1) % root.pages.length
    }
    Shortcut {
        sequences: [StandardKey.PreviousChild]
        onActivated: root.currentPage = (root.currentPage - 1 + root.pages.length) % root.pages.length
    }

    ColumnLayout {
        anchors {
            fill: parent
            margins: contentPadding
        }

        Item { // Titlebar
            visible: Config.options?.windows.showTitlebar
            Layout.fillWidth: true
            Layout.fillHeight: false
            implicitHeight: Math.max(titleText.implicitHeight, windowControlsRow.implicitHeight)
            RippleButton { // Nav rail toggle, up here to keep the rail itself compact
                id: railToggleButton
                anchors {
                    left: parent.left
                    leftMargin: 8
                    verticalCenter: parent.verticalCenter
                }
                implicitWidth: 35
                implicitHeight: 35
                buttonRadius: Appearance.rounding.full
                focus: root.visible
                downAction: () => {
                    navRail.expanded = !navRail.expanded;
                }
                rotation: navRail.expanded ? 0 : -180
                Behavior on rotation {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    iconSize: 20
                    color: Appearance.colors.colOnLayer1
                    text: navRail.expanded ? "menu_open" : "menu"
                }
            }
            StyledText {
                id: titleText
                anchors {
                    left: Config.options.windows.centerTitle ? undefined : railToggleButton.right
                    horizontalCenter: Config.options.windows.centerTitle ? parent.horizontalCenter : undefined
                    verticalCenter: parent.verticalCenter
                    leftMargin: 12
                }
                color: Appearance.colors.colOnLayer0
                text: Translation.tr("Settings")
                font {
                    family: Appearance.font.family.title
                    pixelSize: Appearance.font.pixelSize.title
                    variableAxes: Appearance.font.variableAxes.title
                }
            }
            RowLayout { // Window controls row
                id: windowControlsRow
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                RippleButton {
                    buttonRadius: Appearance.rounding.full
                    implicitWidth: 35
                    implicitHeight: 35
                    onClicked: root.closeRequested()
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        text: "close"
                        iconSize: 20
                    }
                }
            }
        }

        RowLayout { // Window content with navigation rail and content pane
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: contentPadding
            Item {
                id: navRailWrapper
                Layout.fillHeight: true
                Layout.margins: 5
                implicitWidth: navRail.expanded ? 150 : configFileButton.baseSize
                Behavior on implicitWidth {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                NavigationRail { // Window content with navigation rail and content pane
                    id: navRail
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                        bottom: parent.bottom
                    }
                    spacing: 10
                    expanded: root.width > 900

                    StyledFlickable { // The page list outgrows the window; let it scroll
                        Layout.fillHeight: true
                        Layout.fillWidth: true
                        clip: true
                        contentWidth: navTabs.implicitWidth
                        contentHeight: navTabs.implicitHeight + 25
                        ScrollBar.vertical: null // KOOMPI design: scrollable surfaces stay clean, no scrollbar

                        NavigationRailTabArray {
                            id: navTabs
                            y: 25
                            currentIndex: root.currentPage
                            expanded: navRail.expanded
                            Repeater {
                                model: root.pages
                                NavigationRailButton {
                                    required property var index
                                    required property var modelData
                                    toggled: root.currentPage === index
                                    onPressed: root.currentPage = index;
                                    expanded: navRail.expanded
                                    buttonIcon: modelData.icon
                                    buttonIconRotation: modelData.iconRotation || 0
                                    buttonText: modelData.name
                                    showToggledHighlight: false
                                    showCollapsedLabel: false
                                }
                            }
                            NavigationRailButton {
                                id: configFileButton
                                toggled: false
                                expanded: navRail.expanded
                                buttonIcon: "edit"
                                buttonText: Translation.tr("Edit config file")
                                showToggledHighlight: false
                                showCollapsedLabel: false
                                onClicked: Qt.openUrlExternally(`${Directories.config}/koompi/config.json`)
                            }
                        }
                    }
                }
            }
            Rectangle { // Content container
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: Appearance.m3colors.m3surfaceContainerLow
                radius: Appearance.rounding.windowRounding - root.contentPadding

                Loader {
                    id: pageLoader
                    anchors.fill: parent
                    opacity: 1.0

                    active: Config.ready
                    Component.onCompleted: {
                        source = root.pagePath(root.currentPage)
                    }

                    Connections {
                        target: root
                        function onCurrentPageChanged() {
                            switchAnim.complete();
                            switchAnim.start();
                        }
                    }

                    SequentialAnimation {
                        id: switchAnim

                        NumberAnimation {
                            target: pageLoader
                            properties: "opacity"
                            from: 1
                            to: 0
                            duration: Appearance.animationDuration.snap
                            easing.type: Appearance.animation.elementMoveExit.type
                            easing.bezierCurve: Appearance.animationCurves.emphasizedFirstHalf
                        }
                        ParallelAnimation {
                            PropertyAction {
                                target: pageLoader
                                property: "source"
                                value: root.pagePath(root.currentPage)
                            }
                            PropertyAction {
                                target: pageLoader
                                property: "anchors.topMargin"
                                value: 20
                            }
                        }
                        ParallelAnimation {
                            NumberAnimation {
                                target: pageLoader
                                properties: "opacity"
                                from: 0
                                to: 1
                                duration: Appearance.animationDuration.fast
                                easing.type: Appearance.animation.elementMoveEnter.type
                                easing.bezierCurve: Appearance.animationCurves.emphasizedLastHalf
                            }
                            NumberAnimation {
                                target: pageLoader
                                properties: "anchors.topMargin"
                                to: 0
                                duration: Appearance.animationDuration.fast
                                easing.type: Appearance.animation.elementMoveEnter.type
                                easing.bezierCurve: Appearance.animationCurves.emphasizedLastHalf
                            }
                        }
                    }
                }
            }
        }
    }
}
