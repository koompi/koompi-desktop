import qs.services
import qs.modules.common
import qs.modules.common.models
import qs.modules.common.functions
import QtQuick

QtObject {
    id: root

    readonly property Component rowComp: Component {
        LauncherSearchResult {}
    }

    readonly property var prepared: SettingsPages.list.map(page => ({
        name: Fuzzy.prepare(`${page.name} ${SettingsPages.pageArg(page)}`),
        entry: page
    }))

    function rows(search: string): var {
        const matches = search.trim() === "" ? SettingsPages.list : Fuzzy.go(search, root.prepared, {
            all: true,
            key: "name"
        }).map(r => r.obj.entry);
        return matches.map(page => root.rowComp.createObject(null, {
            key: `settings|${page.name}`,
            name: page.name,
            type: Translation.tr("Settings"),
            verb: Translation.tr("Open"),
            iconName: page.icon,
            iconType: LauncherSearchResult.IconType.Material,
            scopePrefix: Config.options.search.prefix.settings,
            execute: () => {
                SettingsPages.open(page);
            }
        }));
    }
}
