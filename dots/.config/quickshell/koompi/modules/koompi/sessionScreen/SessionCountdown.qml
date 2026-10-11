import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: root

    property string title
    property string titleOne
    property string nowText
    property int seconds: 10
    property int remaining: seconds
    readonly property bool labelled: cancelButton.labelVisible && nowButton.labelVisible
    readonly property string focused: nowButton.activeFocus ? "now" : cancelButton.activeFocus ? "cancel" : "none"

    signal cancelled
    signal confirmed

    spacing: 18

    Component.onCompleted: tick.start()

    Timer {
        id: tick
        interval: 1000
        repeat: true
        onTriggered: {
            root.remaining -= 1;
            if (root.remaining <= 0) {
                tick.stop();
                root.confirmed();
            }
        }
    }

    // a key still held from the tile that opened this must not cancel it at once
    // true when the key is spent; Enter and Space are left to the focused button
    function handleKey(event): bool {
        // a modifier alone is half of a chord, not an answer
        if (event.isAutoRepeat || [Qt.Key_Shift, Qt.Key_Control, Qt.Key_Alt, Qt.Key_AltGr, Qt.Key_Meta, Qt.Key_Super_L, Qt.Key_Super_R, Qt.Key_CapsLock].includes(event.key))
            return true;
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space)
            return false;
        if (event.key === Qt.Key_Left || event.key === Qt.Key_Right || event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab)
            (nowButton.activeFocus ? cancelButton : nowButton).forceActiveFocus();
        else
            root.cancelled();
        return true;
    }

    function takeFocus() {
        cancelButton.forceActiveFocus();
    }

    Item {
        Layout.alignment: Qt.AlignHCenter
        implicitWidth: 150
        implicitHeight: 150

        CircularProgress {
            anchors.fill: parent
            implicitSize: 150
            lineWidth: 8
            value: root.remaining / root.seconds
            colPrimary: Appearance.colors.colPrimary
            colSecondary: Appearance.colors.colSecondaryContainer
            gapAngle: 0
            animationDuration: 900
            easingType: Easing.Linear
        }
        StyledText {
            anchors.centerIn: parent
            color: Appearance.colors.colOnLayer0
            font.pixelSize: 56
            text: root.remaining
        }
    }

    StyledText {
        Layout.alignment: Qt.AlignHCenter
        font {
            family: Appearance.font.family.title
            pixelSize: Appearance.font.pixelSize.title
            variableAxes: Appearance.font.variableAxes.title
        }
        text: (root.remaining === 1 ? root.titleOne : root.title).arg(root.remaining)
    }

    RowLayout {
        Layout.alignment: Qt.AlignHCenter
        spacing: 15

        SessionActionButton {
            id: cancelButton
            compact: true
            buttonIcon: "close"
            buttonText: Translation.tr("Cancel")
            onClicked: root.cancelled()
            KeyNavigation.right: nowButton
        }
        SessionActionButton {
            id: nowButton
            compact: true
            buttonIcon: "power_settings_new"
            buttonText: root.nowText
            onClicked: root.confirmed()
            KeyNavigation.left: cancelButton
        }
    }
}
