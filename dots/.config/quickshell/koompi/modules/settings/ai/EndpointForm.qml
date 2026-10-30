import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "endpoint-form.js" as Form

/**
 * Add or edit one OpenAI-compatible endpoint. Opens on `entry` (null to add),
 * checks the fields with endpoint-form.js and hands the finished `ai.extraModels`
 * entry to `saved`; problems sit under the field they are about and the typing stays.
 */
ColumnLayout {
    id: root

    property var entry: null
    property var takenIds: []
    property var problems: ({})
    property string format: "openai"
    property bool needsKey: true

    signal saved(var entry)
    signal cancelled()

    Layout.fillWidth: true
    spacing: 4

    function load() {
        const form = Form.formFrom(root.entry, AiProviders.isLocal(root.entry?.endpoint ?? ""));
        nameField.text = form.name;
        baseField.text = form.baseUrl;
        modelField.text = form.model;
        root.format = form.format;
        root.needsKey = form.needsKey;
        root.problems = ({});
    }

    function submit() {
        const form = {
            "name": nameField.text,
            "baseUrl": baseField.text,
            "model": modelField.text,
            "format": root.format,
            "needsKey": root.needsKey,
        };
        root.problems = Form.validate(form, root.takenIds, Translation);
        if (Object.keys(root.problems).length > 0) return;
        root.saved(Form.entryFrom(form, root.entry));
    }

    Component.onCompleted: root.load()

    MaterialTextField {
        id: nameField
        objectName: "endpointName"
        Layout.fillWidth: true
        placeholderText: Translation.tr("Name in the model list (optional)")
    }

    MaterialTextField {
        id: baseField
        objectName: "endpointBase"
        Layout.fillWidth: true
        placeholderText: Translation.tr("Base URL, e.g. https://api.example.com/v1")
        inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoAutoUppercase
        onTextChanged: if (root.problems.baseUrl) root.problems = Object.assign({}, root.problems, { "baseUrl": "" })
    }
    StyledText {
        visible: (root.problems.baseUrl ?? "").length > 0
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colError
        text: root.problems.baseUrl ?? ""
    }

    MaterialTextField {
        id: modelField
        objectName: "endpointModel"
        Layout.fillWidth: true
        placeholderText: Translation.tr("Model id")
        inputMethodHints: Qt.ImhNoAutoUppercase
        onTextChanged: if (root.problems.model) root.problems = Object.assign({}, root.problems, { "model": "" })
    }
    StyledText {
        visible: (root.problems.model ?? "").length > 0
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colError
        text: root.problems.model ?? ""
    }

    ConfigSelectionArray {
        currentValue: root.format
        onSelected: newValue => root.format = newValue
        options: [
            {
                displayName: Translation.tr("Chat Completions"),
                value: "openai"
            },
            {
                displayName: Translation.tr("Responses"),
                value: "responses"
            }
        ]
    }

    ConfigSwitch {
        buttonIcon: "key"
        text: Translation.tr("Needs an API key")
        checked: root.needsKey
        onCheckedChanged: root.needsKey = checked
    }

    RowLayout {
        Layout.fillWidth: true
        Item {
            Layout.fillWidth: true
        }
        DialogButton {
            buttonText: Translation.tr("Cancel")
            onClicked: root.cancelled()
        }
        DialogButton {
            objectName: "endpointSave"
            buttonText: root.entry ? Translation.tr("Save") : Translation.tr("Add endpoint")
            onClicked: root.submit()
        }
    }
}
