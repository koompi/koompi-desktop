import qs.services
import qs.modules.common
import qs.modules.common.models
import qs.modules.common.functions
import QtQuick
import Quickshell

QtObject {
    id: root

    readonly property Component rowComp: Component {
        LauncherSearchResult {}
    }

    readonly property bool workSafetyActive: {
        const enabled = Config.options.workSafety.enable.clipboard;
        const sensitiveNetwork = (StringUtils.stringListContainsSubstring(Network.networkName.toLowerCase(), Config.options.workSafety.triggerCondition.networkNameKeywords));
        return enabled && sensitiveNetwork;
    }

    function containsUnsafeLink(entry) {
        if (entry == undefined)
            return false;
        const unsafeKeywords = Config.options.workSafety.triggerCondition.linkKeywords;
        return StringUtils.stringListContainsSubstring(entry.toLowerCase(), unsafeKeywords);
    }

    function action(name: string, icon: string, run, keepOpen = false): var {
        return root.rowComp.createObject(null, {
            name: name,
            iconName: icon,
            iconType: LauncherSearchResult.IconType.Material,
            keepOpen: keepOpen,
            execute: run
        });
    }

    function rows(search: string): var {
        return Cliphist.fuzzyQuery(search).map((entry, index, array) => {
            const mightBlurImage = Cliphist.entryIsImage(entry) && root.workSafetyActive;
            let shouldBlurImage = mightBlurImage;
            if (mightBlurImage) {
                shouldBlurImage = shouldBlurImage && (root.containsUnsafeLink(array[index - 1]) || root.containsUnsafeLink(array[index + 1]));
            }
            const type = `#${entry.match(/^\s*(\S+)/)?.[1] || ""}`;
            return root.rowComp.createObject(null, {
                key: `clipboard|${entry}`,
                rawValue: entry,
                name: StringUtils.cleanCliphistEntry(entry),
                verb: "",
                type: type,
                scopePrefix: Config.options.search.prefix.clipboard,
                execute: () => {
                    Cliphist.copy(entry);
                },
                actions: [root.action(Translation.tr("Copy"), "content_copy", () => Cliphist.copy(entry)), root.action(Translation.tr("Delete"), "delete", () => Cliphist.deleteEntry(entry), true)],
                blurImage: shouldBlurImage
            });
        }).filter(Boolean);
    }

    function emojis(search: string): var {
        return Emojis.fuzzyQuery(search).map(entry => {
            const emoji = entry.match(/^\s*(\S+)/)?.[1] || "";
            return root.rowComp.createObject(null, {
                key: `emoji|${entry}`,
                rawValue: entry,
                name: entry.replace(/^\s*\S+\s+/, ""),
                iconName: emoji,
                iconType: LauncherSearchResult.IconType.Text,
                verb: Translation.tr("Copy"),
                type: Translation.tr("Emoji"),
                execute: () => {
                    Quickshell.clipboardText = entry.match(/^\s*(\S+)/)?.[1];
                }
            });
        }).filter(Boolean);
    }
}
