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

    objectName: `${root.editing ? "cc-edit" : "cc-extra"}-${root.type}`
    visible: root.editing || root.installed
    icon: model?.icon ?? "extension"
    title: model?.name ?? root.type
    detail: root.editing ? (root.installed ? "" : Translation.tr("Not installed")) : (model?.hasStatusText ? (model?.statusText ?? "") : "")
    toggled: root.editing ? CcExtras.listed(root.type) : (model?.toggled ?? false)
    onWord: root.editing ? Translation.tr("Shown") : Translation.tr("On")
    offWord: root.editing ? Translation.tr("Hidden") : Translation.tr("Off")
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
