import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentSection {
    icon: "overview_key"
    title: Translation.tr("Overview")

    ConfigSwitch {
        buttonIcon: "check"
        text: Translation.tr("Enable")
        checked: Config.options.overview.enable
        onCheckedChanged: {
            Config.options.overview.enable = checked;
        }
    }
}
