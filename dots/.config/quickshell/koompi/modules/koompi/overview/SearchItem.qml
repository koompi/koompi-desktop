// pragma NativeMethodBehavior: AcceptThisObject
import qs
import qs.services
import qs.modules.common
import qs.modules.common.models
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Hyprland

RippleButton {
    id: root
    property LauncherSearchResult entry
    property string query
    property bool entryShown: entry?.shown ?? true
    property string itemType: entry?.type ?? Translation.tr("App")
    property string itemName: entry?.name ?? ""
    property var iconType: entry?.iconType
    property string iconName: entry?.iconName ?? ""
    property var itemExecute: entry?.execute
    property var fontType: switch(entry?.fontType) {
        case LauncherSearchResult.FontType.Monospace:
            return "monospace"
        case LauncherSearchResult.FontType.Normal:
            return "main"
        default:
            return "main"
    }
    property string itemClickActionName: entry?.verb ?? "Open"
    property string bigText: entry?.iconType === LauncherSearchResult.IconType.Text ? entry?.iconName ?? "" : ""
    property string materialSymbol: entry.iconType === LauncherSearchResult.IconType.Material ? entry?.iconName ?? "" : ""
    property string cliphistRawString: entry?.rawValue ?? ""
    property bool blurImage: entry?.blurImage ?? false

    // Rows out of the command tree carry two fields no other provider sets
    // (services/commandTree/CommandResult.qml). Read through a var so the
    // lookup stays dynamic on every row that has none of them.
    readonly property var commandFields: root.entry
    readonly property string itemGroup: root.commandFields?.group ?? ""
    readonly property string itemState: root.commandFields?.stateText ?? ""
    // Set on the first row of each group (the action scope's grouped view, the
    // recent apps), so a heading costs no extra row and the arrow keys still
    // only meet results.
    readonly property string itemHeading: root.entry?.heading ?? ""
    readonly property real headingHeight: root.itemHeading === "" ? 0 : headingText.implicitHeight + root.buttonVerticalPadding * 2
    
    visible: root.entryShown
    property int horizontalMargin: 10
    property int buttonHorizontalPadding: 10
    property int buttonVerticalPadding: 6
    property bool keyboardDown: false
    // the pointer anywhere over the row, including over its own buttons
    HoverHandler {
        id: rowHover
    }
    readonly property bool selected: (root.hovered || root.focus || rowHover.hovered)
    readonly property int smallText: Math.max(12, Appearance.font.pixelSize.smaller)
    readonly property var shortcutCaps: root.commandFields?.shortcut ?? []

    implicitHeight: rowLayout.implicitHeight + root.buttonVerticalPadding * 2 + root.headingHeight
    implicitWidth: rowLayout.implicitWidth + root.buttonHorizontalPadding * 2
    buttonRadius: Appearance.rounding.normal
    colBackground: (root.down || root.keyboardDown) ? Appearance.colors.colPrimaryContainerActive : 
        (selected ? Appearance.colors.colPrimaryContainer : 
        ColorUtils.transparentize(Appearance.colors.colPrimaryContainer, 1))
    colBackgroundHover: Appearance.colors.colPrimaryContainer
    colRipple: Appearance.colors.colPrimaryContainerActive
    property color colForeground: selected ? Appearance.colors.colOnPrimaryContainer : Appearance.m3colors.m3onSurface

    readonly property string highlightPrefix: `<u><font color="${Appearance.colors.colPrimary}">`
    readonly property string highlightSuffix: `</font></u>`
    // Note that this highlighting is independent from the search
    // It's close, but does not accurately represent how the fuzzy algorithm works
    function highlightContent(content, query) {
        if (!query || query.length === 0 || content == query || fontType === "monospace")
            return StringUtils.escapeHtml(content);

        let contentLower = content.toLowerCase();
        let queryLower = query.toLowerCase();

        let result = "";
        let lastIndex = 0;
        let qIndex = 0;

        for (let i = 0; i < content.length && qIndex < query.length; i++) {
            if (contentLower[i] === queryLower[qIndex]) {
                // Add non-highlighted part (escaped)
                if (i > lastIndex)
                    result += StringUtils.escapeHtml(content.slice(lastIndex, i));
                // Add highlighted character (escaped)
                result += root.highlightPrefix + StringUtils.escapeHtml(content[i]) + root.highlightSuffix;
                lastIndex = i + 1;
                qIndex++;
            }
        }
        // Add the rest of the string (escaped)
        if (lastIndex < content.length)
            result += StringUtils.escapeHtml(content.slice(lastIndex));

        return result;
    }
    property string displayContent: highlightContent(root.itemName, root.query)

    property list<string> urls: {
        if (!root.itemName) return [];
        // Regular expression to match URLs
        const urlRegex = /https?:\/\/[^\s<>"{}|\\^`[\]]+/gi;
        const matches = root.itemName?.match(urlRegex)
            ?.filter(url => !url.includes("…")) // Elided = invalid
        return matches ? matches : [];
    }
    
    PointingHandInteraction {}

    background {
        anchors.fill: root
        anchors.leftMargin: root.horizontalMargin
        anchors.rightMargin: root.horizontalMargin
        // The heading belongs to the group, not to the row, so the highlight
        // and the ripple start below it.
        anchors.topMargin: root.headingHeight
    }

    StyledText {
        id: headingText
        visible: root.itemHeading !== ""
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.topMargin: root.buttonVerticalPadding
        anchors.leftMargin: root.horizontalMargin + root.buttonHorizontalPadding
        text: root.itemHeading
        font.pixelSize: root.smallText
        font.weight: Font.DemiBold
        color: Appearance.colors.colSubtext
    }

    onClicked: {
        if (!root.entry?.keepOpen)
            GlobalStates.searchOpen = false
        root.itemExecute()
    }
    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Delete && event.modifiers === Qt.ShiftModifier) {
            const deleteAction = root.entry.actions.find(action => action.name == Translation.tr("Delete"));

            if (deleteAction) {
                deleteAction.execute()
            }
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.keyboardDown = true
            root.clicked()
            event.accepted = true;
        } else if (event.key === Qt.Key_Space && event.modifiers === Qt.NoModifier && (root.entry?.previewPath ?? "") !== "") {
            FileSearch.toggleQuicklook(root.entry.previewPath)
            event.accepted = true;
        }
    }
    Keys.onReleased: (event) => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.keyboardDown = false
            event.accepted = true;
        }
    }

    RowLayout {
        id: rowLayout
        spacing: iconLoader.sourceComponent === null ? 0 : 10
        anchors.fill: parent
        anchors.topMargin: root.headingHeight
        anchors.leftMargin: root.horizontalMargin + root.buttonHorizontalPadding
        anchors.rightMargin: root.horizontalMargin + root.buttonHorizontalPadding

        // Icon
        Loader {
            id: iconLoader
            active: true
            sourceComponent: switch(root.iconType) {
                case LauncherSearchResult.IconType.Material:
                    return materialSymbolComponent
                case LauncherSearchResult.IconType.Text:
                    return bigTextComponent
                case LauncherSearchResult.IconType.System:
                    return iconImageComponent
                case LauncherSearchResult.IconType.None:
                    return null
                default:
                    return null
            }
        }

        Component {
            id: iconImageComponent
            AppIconPlate {
                iconName: root.iconName
                label: root.itemName
                size: 32
            }
        }

        Component {
            id: materialSymbolComponent
            MaterialSymbol {
                text: root.materialSymbol
                iconSize: 30
                color: root.colForeground
            }
        }

        Component {
            id: bigTextComponent
            StyledText {
                text: root.bigText
                font.pixelSize: Appearance.font.pixelSize.larger
                color: root.colForeground
            }
        }

        // Main text
        ColumnLayout {
            id: contentColumn
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 0
            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideMiddle
                font.pixelSize: root.smallText
                color: root.selected ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colSubtext
                visible: root.itemType && root.itemType != Translation.tr("App")
                text: root.itemType
            }
            RowLayout {
                Loader { // Checkmark for copied clipboard entry
                    visible: itemName == Quickshell.clipboardText && root.cliphistRawString
                    active: itemName == Quickshell.clipboardText && root.cliphistRawString
                    sourceComponent: Rectangle {
                        implicitWidth: activeText.implicitHeight
                        implicitHeight: activeText.implicitHeight
                        radius: Appearance.rounding.full
                        color: Appearance.colors.colPrimary
                        MaterialSymbol {
                            id: activeText
                            anchors.centerIn: parent
                            text: "check"
                            font.pixelSize: Appearance.font.pixelSize.normal
                            color: Appearance.m3colors.m3onPrimary
                        }
                    }
                }
                Repeater { // Favicons for links
                    model: root.query == root.itemName ? [] : root.urls
                    Favicon {
                        required property var modelData
                        size: parent.height
                        url: modelData
                    }
                }
                StyledText { // Item name/content
                    Layout.fillWidth: true
                    id: nameText
                    textFormat: Text.StyledText // RichText also works, but StyledText ensures elide work
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.family: Appearance.font.family[root.fontType]
                    color: root.colForeground
                    horizontalAlignment: Text.AlignLeft
                    elide: Text.ElideRight
                    text: root.selected ? StringUtils.escapeHtml(root.itemName) : root.displayContent
                }
            }
            Loader { // Clipboard image preview
                active: root.cliphistRawString && Cliphist.entryIsImage(root.cliphistRawString)
                sourceComponent: CliphistImage {
                    Layout.fillWidth: true
                    entry: root.cliphistRawString
                    maxWidth: contentColumn.width
                    maxHeight: 140
                    blur: root.blurImage
                }
            }
        }

        // What the switch is doing right now: "off", "16 px", "3".
        StyledText {
            Layout.fillWidth: false
            visible: root.itemState !== ""
            font.pixelSize: root.smallText
            color: root.selected ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colSubtext
            horizontalAlignment: Text.AlignRight
            text: root.itemState
        }

        // Groups are headings, not levels, so a leaf found in the flat search
        // says which one it came from instead of being reached through it.
        StyledText {
            Layout.fillWidth: false
            visible: root.itemGroup !== ""
            font.pixelSize: root.smallText
            color: root.selected ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colSubtext
            horizontalAlignment: Text.AlignRight
            text: `· ${root.itemGroup}`
        }

        // The chord that does the same thing, so the key gets learned
        Row {
            visible: root.shortcutCaps.length > 0
            Layout.fillWidth: false
            spacing: 3
            Repeater {
                model: root.shortcutCaps
                delegate: KeyboardKey {
                    required property string modelData
                    key: modelData
                    pixelSize: root.smallText
                }
            }
        }

        // Action text
        StyledText {
            Layout.fillWidth: false
            visible: root.selected
            id: clickAction
            font.pixelSize: Appearance.font.pixelSize.normal
            color: Appearance.colors.colOnPrimaryContainer
            horizontalAlignment: Text.AlignRight
            text: root.itemClickActionName
        }

        // Only the row under the cursor offers its other actions, each by name
        RowLayout {
            Layout.alignment: Qt.AlignVCenter
            visible: root.selected
            spacing: 4
            Repeater {
                model: root.selected ? (root.entry.actions ?? []).slice(0, 4) : []
                delegate: RippleButton {
                    id: actionButton
                    required property var modelData
                    implicitHeight: 30
                    implicitWidth: actionLabel.implicitWidth + 20
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colSecondaryContainer
                    colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                    colRipple: Appearance.colors.colSecondaryContainerActive

                    contentItem: StyledText {
                        id: actionLabel
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        font.pixelSize: root.smallText
                        color: Appearance.colors.colOnSecondaryContainer
                        text: actionButton.modelData.name
                    }

                    onClicked: {
                        if (!actionButton.modelData.keepOpen)
                            GlobalStates.searchOpen = false
                        actionButton.modelData.execute()
                    }
                }
            }
        }

    }
}
