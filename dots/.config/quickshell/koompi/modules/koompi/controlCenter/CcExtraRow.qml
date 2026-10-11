import qs.services
import qs.modules.common
import qs.modules.common.models.quickToggles
import QtQuick

CcRow {
    id: root

    required property string type
    property bool editing: false
    readonly property QuickToggleModel model: loader.item
    readonly property bool installed: model?.available ?? false
    // a mode with more than two settings reads its setting by name, not On or Off
    readonly property bool isMode: root.type === "powerProfile"

    objectName: `${root.editing ? "cc-edit" : "cc-extra"}-${root.type}`
    visible: root.editing ? root.type !== "powerProfile" : root.installed
    icon: model?.icon || "extension"
    title: model?.name ?? root.type
    detail: root.editing ? (root.installed ? "" : Translation.tr("Not installed")) : (!root.isMode && model?.hasStatusText ? (model?.statusText ?? "") : "")
    toggled: root.editing ? CcExtras.listed(root.type) : (model?.toggled ?? false)
    onWord: root.editing ? Translation.tr("Shown") : root.isMode ? Translation.tr(model?.statusText ?? "") : Translation.tr("On")
    offWord: root.editing ? Translation.tr("Hidden") : root.isMode ? Translation.tr(model?.statusText ?? "") : Translation.tr("Off")
    onActivated: {
        if (root.editing)
            CcExtras.setListed(root.type, !CcExtras.listed(root.type));
        else
            root.model.mainAction();
    }

    Loader {
        id: loader
        sourceComponent: CcExtras.componentFor(root.type)
    }
}
