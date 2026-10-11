import "periodic_table.js" as PTable
import QtQuick

Item {
    id: root
    readonly property var elements: PTable.elements
    readonly property var series: PTable.series
    readonly property int columns: elements[0].length
    readonly property int rows: elements.length + series.length
    property real spacing: 6
    // the most a tile gets; a smaller page gives the table less room and the tiles shrink to it
    property real tileSize: 70
    readonly property real tileWidth: root.fit(root.width, root.columns)
    readonly property real tileHeight: root.fit(root.height, root.rows)

    function fit(room, count) {
        return Math.max(0, Math.min(root.tileSize, Math.floor((room - root.spacing * (count - 1)) / count)));
    }

    implicitWidth: root.columns * root.tileSize + (root.columns - 1) * root.spacing
    implicitHeight: root.rows * root.tileSize + (root.rows - 1) * root.spacing

    Column {
        id: mainLayout
        anchors.centerIn: parent
        spacing: root.spacing

        Repeater { // Main table rows
            model: root.elements

            delegate: Row { // Table cells
                id: tableRow
                spacing: root.spacing
                required property var modelData

                Repeater {
                    model: tableRow.modelData
                    delegate: ElementTile {
                        required property var modelData
                        element: modelData
                        width: root.tileWidth
                        height: root.tileHeight
                    }
                }
            }
        }

        Repeater { // Lanthanides and actinides
            model: root.series

            delegate: Row { // Table cells
                id: seriesTableRow
                spacing: root.spacing
                required property var modelData

                Repeater {
                    model: seriesTableRow.modelData
                    delegate: ElementTile {
                        required property var modelData
                        element: modelData
                        width: root.tileWidth
                        height: root.tileHeight
                    }
                }
            }
        }
    }
}
