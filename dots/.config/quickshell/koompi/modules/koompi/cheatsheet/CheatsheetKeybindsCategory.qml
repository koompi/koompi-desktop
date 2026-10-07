pragma ComponentBehavior: Bound

import "cheatsheet-binds.js" as CheatsheetBinds
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell

Column {
    id: root
    required property string categoryName
    readonly property bool isCategorized: categoryName?.length > 0
    // Ids of the binds the search keeps, or null for every bind
    property var matchIds: null
    // The row Enter would run
    property int firstMatchId: -1
    required property var activate
    property int maxBindWidth: 0
    property real columnSpacing: 40
    property real titleSpacing: 7

    // Excellent symbol explaination and source :
    // http://xahlee.info/comp/unicode_computing_symbols.html
    // https://www.nerdfonts.com/cheat-sheet
    property var macSymbolMap: ({
        "Ctrl": "󰘴",
        "Alt": "󰘵",
        "Shift": "󰘶",
        "Space": "󱁐",
        "Tab": "↹",
        "Equal": "󰇼",
        "Minus": "",
        "Print": "",
        "BackSpace": "󰭜",
        "Delete": "⌦",
        "Return": "󰌑",
        "Period": ".",
        "Escape": "⎋"
      })
    property var functionSymbolMap: ({
        "F1":  "󱊫",
        "F2":  "󱊬",
        "F3":  "󱊭",
        "F4":  "󱊮",
        "F5":  "󱊯",
        "F6":  "󱊰",
        "F7":  "󱊱",
        "F8":  "󱊲",
        "F9":  "󱊳",
        "F10": "󱊴",
        "F11": "󱊵",
        "F12": "󱊶",
    })

    property var mouseSymbolMap: ({
        "mouse_up": "󱕐",
        "mouse_down": "󱕑",
        "mouse:272": "L󰍽",
        "mouse:273": "R󰍽",
    })

    // Only what needs translating or a symbol; every other key name is in cheatsheet-binds.js.
    property var keySubstitutions: Object.assign({
        "Super": "􀀀",
        "mouse_up": Translation.tr("Scroll") + " ↓",
        "mouse_down": Translation.tr("Scroll") + " ↑",
        "mouse:272": Translation.tr("Left click"),
        "mouse:273": Translation.tr("Right click"),
        "mouse:274": Translation.tr("Middle click"),
        "mouse:275": Translation.tr("Back"),
        "mouse:276": Translation.tr("Forward"),
      },
      !!Config.options.cheatsheet.superKey ? {
          "Super": Config.options.cheatsheet.superKey,
      }: {},
      Config.options.cheatsheet.useMacSymbol ? macSymbolMap : {},
      Config.options.cheatsheet.useFnSymbol ? functionSymbolMap : {},
      Config.options.cheatsheet.useMouseSymbol ? mouseSymbolMap : {},
    )

    readonly property var rows: CheatsheetBinds.buildRows(HyprlandKeybinds.keybinds.map(bind => ({
        id: bind.id,
        mods: HyprlandKeybinds.modifiersOf(bind.modmask),
        key: HyprlandKeybinds.keyOf(bind),
        description: bind.description,
        dispatchable: HyprlandKeybinds.dispatchable(bind)
    })), root.categoryName, root.keySubstitutions)

    visible: repeater.model.length > 0
    spacing: titleSpacing

    StyledText {
        text: root.isCategorized ? root.categoryName : "Uncategorized"
        font.pixelSize: Appearance.font.pixelSize.title
    }

    function shown(row) {
        return root.matchIds === null || row.ids.some(id => root.matchIds.includes(id));
    }

    Column {
        spacing: 4
        Repeater {
            id: repeater
            model: root.rows.filter(row => root.shown(row))
            delegate: BindLine {
                required property var modelData
                row: modelData
            }
        }
    }

    // A row that can be dispatched is a button: hover lights it, a click runs the
    // bind and closes the sheet. Rows that cannot (mouse drags, submaps, Lua
    // closures) stay plain text.
    component BindLine: Rectangle {
        id: bindLine
        required property var row
        readonly property bool primary: root.firstMatchId >= 0 && row.ids.includes(root.firstMatchId)
        // Enter runs the first match, so the row that holds it runs that bind too
        readonly property int runId: primary ? root.firstMatchId : row.runId
        readonly property bool dispatchable: runId >= 0
        property real horizontalPadding: 6

        implicitWidth: bindContent.implicitWidth + horizontalPadding * 2
        implicitHeight: bindContent.implicitHeight + 4
        radius: Appearance.rounding.small
        color: primary ? Appearance.colors.colSecondaryContainer
            : bindMouse.containsMouse ? Appearance.colors.colLayer1Hover : "transparent"

        MouseArea {
            id: bindMouse
            anchors.fill: parent
            enabled: bindLine.dispatchable
            hoverEnabled: bindLine.dispatchable
            cursorShape: bindLine.dispatchable ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: root.activate(HyprlandKeybinds.keybinds[bindLine.runId])
        }

        Row {
            id: bindContent
            x: bindLine.horizontalPadding
            anchors.verticalCenter: parent.verticalCenter
            spacing: 16
            Column {
                width: root.maxBindWidth
                spacing: 4
                Repeater {
                    id: chordLines
                    model: bindLine.row.chords
                    delegate: ChordLine {
                        required property int index
                        required property var modelData
                        chord: modelData
                        last: index === bindLine.row.chords.length - 1
                    }
                }
            }
            Item {
                y: Math.max(0, ((chordLines.itemAt(0)?.implicitHeight ?? 0) - implicitHeight) / 2)
                implicitWidth: commentText.implicitWidth + root.columnSpacing
                implicitHeight: commentText.implicitHeight
                StyledText {
                    id: commentText
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    font.pixelSize: Config.options.cheatsheet.fontSize.comment || Appearance.font.pixelSize.smaller
                    text: bindLine.row.text
                }
            }
        }
    }

    component ChordLine: Row {
        id: chordLine
        required property var chord
        required property bool last
        spacing: 4
        Component.onCompleted: root.maxBindWidth = Math.max(root.maxBindWidth, implicitWidth)

        Repeater {
            model: CheatsheetBinds.keycaps(chordLine.chord.mods, Config.options.cheatsheet.splitButtons)
            delegate: KeyboardKey {
                required property var modelData
                key: modelData
                pixelSize: Config.options.cheatsheet.fontSize.key
            }
        }
        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            visible: chordLine.chord.key.length > 0 && chordLine.chord.mods.length > 0
            text: "+"
        }
        KeyboardKey {
            anchors.verticalCenter: parent.verticalCenter
            visible: chordLine.chord.key.length > 0
            key: chordLine.chord.key
            pixelSize: Config.options.cheatsheet.fontSize.key
            color: Appearance.colors.colOnLayer0
        }
        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            visible: !chordLine.last
            text: Translation.tr("or")
            color: Appearance.colors.colSubtext
        }
    }
}
