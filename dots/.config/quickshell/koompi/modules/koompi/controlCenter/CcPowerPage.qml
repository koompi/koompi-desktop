import qs.services
import qs.modules.common
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: root
    spacing: 0

    readonly property var modes: PowerSaving.hasPerformanceProfile ? ["power-saver", "balanced", "performance"] : ["power-saver", "balanced"]
    readonly property var names: ({
            "power-saver": Translation.tr("Power Saver"),
            "balanced": Translation.tr("Balanced"),
            "performance": Translation.tr("Performance")
        })

    Repeater {
        model: root.modes
        delegate: CcChoice {
            required property string modelData
            objectName: "cc-power-" + modelData
            title: root.names[modelData]
            current: PowerSaving.profile === modelData
            onPicked: PowerSaving.setProfile(modelData)
        }
    }
}
