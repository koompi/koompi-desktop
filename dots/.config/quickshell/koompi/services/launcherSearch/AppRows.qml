import qs.services
import qs.modules.common
import qs.modules.common.models
import qs.modules.common.functions
import QtQuick

QtObject {
    id: root

    readonly property int recentLimit: 6
    readonly property Component rowComp: Component {
        LauncherSearchResult {}
    }

    function row(entry, type, heading = ""): var {
        return root.rowComp.createObject(null, {
            key: `app|${entry.id}`,
            type: type,
            heading: heading,
            id: entry.id,
            name: entry.name,
            iconName: entry.icon,
            iconType: LauncherSearchResult.IconType.System,
            verb: Translation.tr("Open"),
            scopePrefix: Config.options.search.prefix.app,
            execute: () => {
                // orders the Launchpad and fills Recent
                LaunchpadUsage.record(entry.id);
                LauncherSearch.launch(entry);
            },
            comment: entry.comment,
            runInTerminal: entry.runInTerminal,
            genericName: entry.genericName,
            keywords: entry.keywords,
            actions: entry.actions.map(action => {
                return root.rowComp.createObject(null, {
                    name: action.name,
                    iconName: action.icon,
                    iconType: LauncherSearchResult.IconType.System,
                    execute: () => LauncherSearch.launch(entry, action.command)
                });
            })
        });
    }

    function matches(search: string): var {
        return AppSearch.fuzzyQuery(search).map(entry => root.row(entry, Translation.tr("App")));
    }

    // Before anything is typed: the apps reached for lately, by the Launchpad's
    // frecency, under one heading. Nothing launched yet is an empty list and the
    // panel stays the resting pill.
    function recent(): var {
        return AppSearch.list.filter(entry => LaunchpadUsage.score(entry.id) > 0).sort((a, b) => LaunchpadUsage.score(b.id) - LaunchpadUsage.score(a.id)).slice(0, root.recentLimit).map((entry, i) => root.row(entry, Translation.tr("App"), i === 0 ? Translation.tr("Recent") : ""));
    }
}
