import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Pipewire

ColumnLayout {
    id: root
    spacing: 0

    component Heading: StyledText {
        Layout.fillWidth: true
        Layout.leftMargin: Appearance.spacing.normal
        Layout.topMargin: Appearance.spacing.small
        font.pixelSize: Appearance.font.pixelSize.smaller
        font.weight: Font.DemiBold
        color: Appearance.colors.colSubtext
    }

    Heading {
        text: Translation.tr("Output")
    }
    Repeater {
        model: Audio.outputDevices
        delegate: CcChoice {
            required property var modelData
            objectName: "cc-output"
            title: Audio.friendlyDeviceName(modelData)
            current: modelData.id === Pipewire.defaultAudioSink?.id
            onPicked: Audio.setDefaultSink(modelData)
        }
    }

    Heading {
        text: Translation.tr("Input")
    }
    Repeater {
        model: Audio.inputDevices
        delegate: CcChoice {
            required property var modelData
            objectName: "cc-input"
            title: Audio.friendlyDeviceName(modelData)
            current: modelData.id === Pipewire.defaultAudioSource?.id
            onPicked: Audio.setDefaultSource(modelData)
        }
    }

    CcLinkRow {
        buttonText: Translation.tr("More settings…")
        page: "sound"
    }
}
