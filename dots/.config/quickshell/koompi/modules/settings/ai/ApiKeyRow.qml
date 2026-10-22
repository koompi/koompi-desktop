import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * One API key: whether it is saved, and add, replace or remove it. The key goes
 * to AiProviders (its KeyGate), which writes the keyring; it is never shown again, held
 * in a property, or written to a file. Removing asks first.
 */
ColumnLayout {
    id: root

    property string keyId: ""
    property string title: ""
    property string logo: ""
    property string icon: "key"
    property string keyLink: ""
    property bool ready: true // the keyring has loaded
    // "", "editing" or "removing"
    property string mode: ""
    property string problem: ""
    readonly property bool saved: root.ready && AiProviders.has(root.keyId)

    Layout.fillWidth: true
    spacing: 4

    function save() {
        if (!AiProviders.store(root.keyId, keyField.text)) {
            root.problem = Translation.tr("Couldn't save the key. Is the keyring unlocked?");
            return;
        }
        keyField.text = "";
        root.problem = "";
        root.mode = "";
    }

    function remove() {
        if (!AiProviders.forget(root.keyId)) {
            root.problem = Translation.tr("Couldn't remove the key. Is the keyring unlocked?");
            return;
        }
        root.problem = "";
        root.mode = "";
    }

    ProviderRow {
        logo: root.logo
        icon: root.icon
        title: root.title
        subtitleIsProblem: root.problem.length > 0
        subtitle: root.problem.length > 0 ? root.problem
            : root.mode === "removing" ? Translation.tr("Remove this key from the keyring?")
            : root.saved ? Translation.tr("Key saved") : Translation.tr("No key")

        RippleButtonWithIcon {
            objectName: "setKey"
            visible: root.mode === "" && root.ready
            materialIcon: root.saved ? "edit" : "key"
            mainText: root.saved ? Translation.tr("Replace") : Translation.tr("Add key")
            onClicked: {
                root.mode = "editing";
                keyField.forceActiveFocus();
            }
        }
        RippleButtonWithIcon {
            objectName: "removeKey"
            visible: root.mode === "" && root.saved
            materialIcon: "delete"
            mainText: Translation.tr("Remove")
            onClicked: root.mode = "removing"
        }
        DialogButton {
            visible: root.mode === "removing"
            buttonText: Translation.tr("Cancel")
            onClicked: root.mode = ""
        }
        DialogButton {
            objectName: "confirmRemove"
            visible: root.mode === "removing"
            buttonText: Translation.tr("Remove key")
            colEnabled: Appearance.colors.colError
            onClicked: root.remove()
        }
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: 34
        visible: root.mode === "editing"

        MaterialTextField {
            id: keyField
            objectName: "keyField"
            Layout.fillWidth: true
            placeholderText: Translation.tr("Paste the API key")
            echoMode: TextInput.Password
            inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
            onAccepted: if (text.trim().length > 0) root.save()
            Keys.onEscapePressed: {
                text = "";
                root.mode = "";
            }
        }
        DialogButton {
            buttonText: Translation.tr("Cancel")
            onClicked: {
                keyField.text = "";
                root.problem = "";
                root.mode = "";
            }
        }
        DialogButton {
            objectName: "saveKey"
            enabled: keyField.text.trim().length > 0
            buttonText: Translation.tr("Save")
            onClicked: root.save()
        }
    }

    StyledText {
        Layout.leftMargin: 34
        visible: root.mode === "editing" && root.keyLink.length > 0
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colPrimary
        text: Translation.tr("Get a key")
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: Qt.openUrlExternally(root.keyLink)
        }
    }
}
