import qs.services
import qs.modules.common
import QtQuick

GlanceCard {
    id: root
    objectName: "w-todo"
    cardIcon: "done_outline"
    cardTitle: Translation.tr("To-do")

    readonly property var unfinished: Todo.list.filter(item => !item.done).slice(0, 3)

    GlanceLine {
        visible: root.unfinished.length === 0
        muted: true
        text: Translation.tr("Nothing to do")
    }
    Repeater {
        model: root.unfinished
        delegate: GlanceLine {
            required property var modelData
            text: modelData.content
        }
    }
}
