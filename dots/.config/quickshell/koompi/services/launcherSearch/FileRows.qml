import "file-format.js" as FileFormat
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

    readonly property string home: FileUtils.trimFileProtocol(Directories.home)

    function modifiedMs(file): real {
        return typeof file.modified === "number" ? file.modified : Date.parse(file.modified);
    }

    // The folder and the date go where the other providers put their type, above
    // the name, so a file row reads "~/Documents · Today 14:02" then its name.
    function describe(file): string {
        const labels = {
            today: Translation.tr("Today"),
            yesterday: Translation.tr("Yesterday")
        };
        return FileFormat.describe(file.path, root.modifiedMs(file), root.home, Date.now(), (date, pattern) => Qt.formatDateTime(date, pattern), labels);
    }

    // fd keeps the last query's hits until the new ones land; a hit that does
    // not contain what is typed now is one of those.
    function stillMatches(file, search: string): bool {
        const needle = search.trim().toLowerCase();
        const haystack = needle.indexOf("/") >= 0 ? file.path : file.name;
        return haystack.toLowerCase().indexOf(needle) >= 0;
    }

    function rows(entries, heading: string): var {
        return entries.map((file, i) => root.rowComp.createObject(null, {
            key: `file|${file.path}`,
            rawValue: file.path,
            previewPath: file.path,
            heading: i === 0 ? heading : "",
            name: file.name,
            type: root.describe(file),
            verb: Translation.tr("Open"),
            iconName: "draft",
            iconType: LauncherSearchResult.IconType.Material,
            scopePrefix: Config.options.search.prefix.file,
            execute: () => {
                FileSearch.open(file.path);
            },
            actions: [root.rowComp.createObject(null, {
                    name: Translation.tr("Show folder"),
                    iconName: "folder_open",
                    iconType: LauncherSearchResult.IconType.Material,
                    execute: () => {
                        FileSearch.revealParent(file.path);
                    }
                })]
        }));
    }

    // Recent documents first, because they need no disk search to answer, then
    // whatever fd has finished finding for the same string.
    function split(search: string): var {
        const recents = FileSearch.fuzzyRecents(search);
        const seen = recents.map(entry => entry.path);
        return {
            recents: recents,
            found: FileSearch.files.filter(file => !seen.includes(file.path) && root.stillMatches(file, search))
        };
    }

    // a path through a dot folder is config, not a document: the blended list leaves it to the file prefix
    function hidden(path: string): bool {
        return path.slice(root.home.length).split("/").some(part => part.startsWith("."));
    }

    function blended(search: string): var {
        const parts = root.split(search);
        return root.rows(parts.recents.concat(parts.found).filter(file => !root.hidden(file.path)), "");
    }

    function scoped(search: string): var {
        const parts = root.split(search);
        return root.rows(parts.recents, Translation.tr("Recent")).concat(root.rows(parts.found, Translation.tr("Files")));
    }
}
