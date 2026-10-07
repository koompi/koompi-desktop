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
    // each chord reports its one-line width, and its widest piece that cannot wrap
    property var chordWidths: []
    property real maxPieceWidth: 0
    // chords wider than this share of the row wrap; the column fits the widest that stays under
    property real chordShare: 0.6
    property real rowPadding: 6
    property real rowSpacing: 12
    property real minDescriptionWidth: 60
    property real titleSpacing: 7
    readonly property real chordWidth: {
        const room = root.width - root.rowPadding * 2 - root.rowSpacing - root.minDescriptionWidth;
        const limit = Math.min(room, (root.width - root.rowPadding * 2) * root.chordShare);
        const fitting = root.chordWidths.filter(width => width <= limit);
        return Math.max(0, Math.min(room, Math.max(root.maxPieceWidth, ...fitting)));
    }
    readonly property real descriptionWidth: Math.max(root.minDescriptionWidth, root.width - root.rowPadding * 2 - root.chordWidth - root.rowSpacing)

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
        "mouse_up": "󱕑",
        "mouse_down": "󱕐",
        "mouse:272": "L󰍽",
        "mouse:273": "R󰍽",
    })

    // Only what needs translating or a symbol; every other key name is in cheatsheet-binds.js.
    property var keySubstitutions: Object.assign({
        "Super": "􀀀",
        "mouse_up": Translation.tr("Scroll") + " ↑",
        "mouse_down": Translation.tr("Scroll") + " ↓",
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

    // one keycap and one line of text, to line the first chord up with its description
    KeyboardKey {
        id: capRuler
        visible: false
    }
    StyledText {
        id: lineRuler
        visible: false
        text: "Ag"
        font.pixelSize: Config.options.cheatsheet.fontSize.comment || Appearance.font.pixelSize.smaller
    }

    function shown(row) {
        return root.matchIds === null || row.ids.some(id => root.matchIds.includes(id));
    }

    Column {
        width: root.width
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

        width: root.width
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
            x: root.rowPadding
            anchors.verticalCenter: parent.verticalCenter
            spacing: root.rowSpacing
            Column {
                objectName: "bindChords"
                width: root.chordWidth
                spacing: 4
                Repeater {
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
                width: root.descriptionWidth
                implicitHeight: commentText.y + commentText.implicitHeight
                StyledText {
                    id: commentText
                    objectName: "bindDescription"
                    y: Math.max(0, (capRuler.implicitHeight - lineRuler.implicitHeight) / 2)
                    width: parent.width
                    wrapMode: Text.Wrap
                    font.pixelSize: lineRuler.font.pixelSize
                    text: bindLine.row.text
                }
            }
        }
    }

    // plus, key and "or" travel together so none wraps alone
    component ChordLine: Flow {
        id: chordLine
        required property var chord
        required property bool last
        width: root.chordWidth
        spacing: 4

        // a piece only has its width after it is made, so each calls this when it gets one
        function measure() {
            let pieces = 0;
            let natural = 0;
            for (let i = 0; i < children.length; i++) {
                const piece = children[i];
                if (piece.implicitWidth <= 0)
                    continue;
                pieces++;
                natural += piece.implicitWidth;
                root.maxPieceWidth = Math.max(root.maxPieceWidth, piece.implicitWidth);
            }
            const width = Math.ceil(natural + Math.max(0, pieces - 1) * spacing);
            if (width > 0 && root.chordWidths.indexOf(width) < 0)
                root.chordWidths = root.chordWidths.concat([width]);
        }

        Repeater {
            model: CheatsheetBinds.keycaps(chordLine.chord.mods, Config.options.cheatsheet.splitButtons)
            delegate: KeyboardKey {
                required property var modelData
                key: modelData
                pixelSize: Config.options.cheatsheet.fontSize.key
                onImplicitWidthChanged: chordLine.measure()
                Component.onCompleted: chordLine.measure()
            }
        }
        Row {
            spacing: chordLine.spacing
            onImplicitWidthChanged: chordLine.measure()
            Component.onCompleted: chordLine.measure()
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
}
