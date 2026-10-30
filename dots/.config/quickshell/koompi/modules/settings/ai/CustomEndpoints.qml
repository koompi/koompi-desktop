import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "endpoint-form.js" as Form

/**
 * Any OpenAI-compatible server, as `ai.extraModels` entries (the ChatGPT plan's
 * own entries are listed under it instead). Each one is a model in the chat's
 * list; one that needs a key gets its key row, stored per server.
 */
ColumnLayout {
    id: root

    readonly property var entries: Config.options.ai.extraModels ?? []
    readonly property var rows: root.entries
        .map((entry, index) => ({ "entry": entry, "index": index }))
        .filter(row => !Form.isPlan(row.entry))
    // -2 closed, -1 adding, else the index being edited
    property int editing: -2
    property int removing: -1

    Layout.fillWidth: true
    spacing: 8

    function takenIdsExcept(index: int): var {
        return ["remote", "local"].concat(root.entries.filter((_, i) => i !== index).map(entry => Form.idOf(entry)));
    }

    function store(index: int, entry) {
        Config.options.ai.extraModels = Form.replaced(root.entries, index, entry);
        root.editing = -2;
    }

    StyledText {
        Layout.fillWidth: true
        visible: root.rows.length === 0 && root.editing === -2
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colSubtext
        wrapMode: Text.Wrap
        text: Translation.tr("None yet. Add any server that speaks OpenAI's API, such as a self-hosted one.")
    }

    Repeater {
        model: root.rows
        delegate: ColumnLayout {
            id: endpointRow
            required property var modelData
            readonly property var entry: modelData.entry
            readonly property int index: modelData.index
            Layout.fillWidth: true
            spacing: 4

            ProviderRow {
                visible: root.editing !== endpointRow.index
                icon: "dns"
                title: `${endpointRow.entry.name ?? ""}`.length > 0 ? endpointRow.entry.name : `${endpointRow.entry.model}`
                subtitleIsProblem: root.removing === endpointRow.index
                subtitle: root.removing === endpointRow.index
                    ? Translation.tr("Remove this endpoint from the model list?")
                    : `${endpointRow.entry.model} · ${Form.hostOf(endpointRow.entry.endpoint) || endpointRow.entry.endpoint}`

                RippleButtonWithIcon {
                    visible: root.removing !== endpointRow.index
                    materialIcon: "edit"
                    mainText: Translation.tr("Edit")
                    onClicked: {
                        root.removing = -1;
                        root.editing = endpointRow.index;
                    }
                }
                RippleButtonWithIcon {
                    visible: root.removing !== endpointRow.index
                    materialIcon: "delete"
                    mainText: Translation.tr("Remove")
                    onClicked: root.removing = endpointRow.index
                }
                DialogButton {
                    visible: root.removing === endpointRow.index
                    buttonText: Translation.tr("Cancel")
                    onClicked: root.removing = -1
                }
                DialogButton {
                    visible: root.removing === endpointRow.index
                    buttonText: Translation.tr("Remove")
                    colEnabled: Appearance.colors.colError
                    onClicked: {
                        root.removing = -1;
                        Config.options.ai.extraModels = Form.removed(root.entries, endpointRow.index);
                    }
                }
            }

            ApiKeyRow {
                Layout.leftMargin: 34
                visible: root.editing !== endpointRow.index && Form.needsKey(endpointRow.entry, AiProviders.isLocal(endpointRow.entry.endpoint))
                ready: AiProviders.ready
                keyId: Form.keyIdOf(endpointRow.entry)
                title: Translation.tr("Key for %1").arg(Form.hostOf(endpointRow.entry.endpoint))
                keyLink: `${endpointRow.entry.key_get_link ?? ""}`
            }

            Loader {
                Layout.fillWidth: true
                active: root.editing === endpointRow.index
                visible: active
                sourceComponent: EndpointForm {
                    entry: endpointRow.entry
                    takenIds: root.takenIdsExcept(endpointRow.index)
                    onSaved: entry => root.store(endpointRow.index, entry)
                    onCancelled: root.editing = -2
                }
            }
        }
    }

    Loader {
        Layout.fillWidth: true
        active: root.editing === -1
        visible: active
        sourceComponent: EndpointForm {
            objectName: "newEndpointForm"
            takenIds: root.takenIdsExcept(-1)
            onSaved: entry => root.store(-1, entry)
            onCancelled: root.editing = -2
        }
    }

    RippleButtonWithIcon {
        objectName: "addEndpoint"
        visible: root.editing === -2
        materialIcon: "add"
        mainText: Translation.tr("Add endpoint")
        onClicked: {
            root.removing = -1;
            root.editing = -1;
        }
    }
}
