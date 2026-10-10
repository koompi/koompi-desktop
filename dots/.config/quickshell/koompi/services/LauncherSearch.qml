pragma Singleton

import "launcherSearch/ranking.js" as Ranking
import qs.services.launcherSearch
import qs.modules.common
import qs.modules.common.models
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Search's one ranked list. A plain query asks every provider and blends the
 * answers under section headings (launcherSearch/ranking.js); a query that
 * starts with a sigil is that sigil's own list, so the sigils stay as filters.
 */
Singleton {
    id: root

    property string query: ""

    signal scopeSwitched

    readonly property list<string> allPrefixes: [Config.options.search.prefix.action, Config.options.search.prefix.app, Config.options.search.prefix.clipboard, Config.options.search.prefix.emojis, Config.options.search.prefix.file, Config.options.search.prefix.math, Config.options.search.prefix.settings, Config.options.search.prefix.shellCommand, Config.options.search.prefix.webSearch, Config.options.search.prefix.window]

    function isPlain(query: string): bool {
        return query !== "" && !root.allPrefixes.some(prefix => query.startsWith(prefix));
    }

    function ensurePrefix(prefix) {
        if (root.allPrefixes.some(i => root.query.startsWith(i))) {
            root.query = prefix + root.query.slice(1);
        } else {
            root.query = prefix + root.query;
        }
    }

    // "Show all N": the same words, inside the sigil that lists the whole set
    function showScope(prefix: string) {
        root.ensurePrefix(prefix);
        root.scopeSwitched();
    }

    // https://specifications.freedesktop.org/menu/latest/category-registry.html
    property list<string> mainRegisteredCategories: ["AudioVideo", "Development", "Education", "Game", "Graphics", "Network", "Office", "Science", "Settings", "System", "Utility"]
    property list<string> appCategories: DesktopEntries.applications.values.reduce((acc, entry) => {
        for (const category of entry.categories) {
            if (!acc.includes(category) && mainRegisteredCategories.includes(category)) {
                acc.push(category);
            }
        }
        return acc;
    }, []).sort()

    readonly property LauncherActions launcherActions: LauncherActions {}
    readonly property AppRows apps: AppRows {}
    readonly property WindowRows windows: WindowRows {}
    readonly property SettingsRows settings: SettingsRows {}
    readonly property ClipboardRows clipboard: ClipboardRows {}
    readonly property FileRows files: FileRows {}
    readonly property Translator translator: Translator {}

    property var allActions: root.launcherActions.all
    property string mathResult: ""

    // the Top Hit of the query last answered, so a late row cannot displace it
    readonly property var pinned: ({
            query: "",
            key: ""
        })

    onQueryChanged: {
        const prefix = Config.options.search.prefix;
        const scopedFile = root.query.startsWith(prefix.file);
        const plain = root.isPlain(root.query);
        FileSearch.query = scopedFile ? StringUtils.cleanPrefix(root.query, prefix.file) : plain ? root.query : "";
        root.translator.request(plain ? (Ranking.translateText(root.query, "translate") ?? "") : "");
        if (plain || root.query.startsWith(prefix.math))
            nonAppResultsTimer.restart();
    }

    Timer {
        id: nonAppResultsTimer
        interval: Config.options.search.nonAppResultDelay
        onTriggered: {
            let expr = root.query;
            if (expr.startsWith(Config.options.search.prefix.math)) {
                expr = expr.slice(Config.options.search.prefix.math.length);
            }
            mathProc.calculateExpression(expr);
        }
    }

    Process {
        id: mathProc
        property list<string> baseCommand: ["qalc", "-t"]
        function calculateExpression(expression) {
            mathProc.running = false;
            mathProc.command = baseCommand.concat(expression);
            mathProc.running = true;
        }
        stdout: SplitParser {
            onRead: data => {
                root.mathResult = data;
            }
        }
    }

    function windowResults(search: string): var {
        return root.windows.rows(search);
    }

    // DesktopEntry.execute() cannot be wrapped; koompi-launch puts the app in app.slice for oomd
    function launch(entry, command = entry.command) {
        const argv = ["koompi-launch", "--registered", "--id", entry.id];
        if (entry.workingDirectory)
            argv.push("--cwd", entry.workingDirectory);
        if (entry.runInTerminal)
            argv.push("--terminal", Config.options.apps.terminal);
        LaunchFeedback.begin(entry);
        Quickshell.execDetached([...argv, "--", ...command]);
    }

    // The scopes worth teaching, in the order they earn their place. Math,
    // commands and web search are left out because they already answer without
    // a prefix. Labels read off the config, so a rebound prefix relabels itself.
    readonly property var scopeHints: [
        ({
                prefix: Config.options.search.prefix.window,
                label: Translation.tr("Windows")
            }),
        ({
                prefix: Config.options.search.prefix.settings,
                label: Translation.tr("Settings")
            }),
        ({
                prefix: Config.options.search.prefix.file,
                label: Translation.tr("Files")
            }),
        ({
                prefix: Config.options.search.prefix.clipboard,
                label: Translation.tr("Clipboard")
            }),
        ({
                prefix: Config.options.search.prefix.emojis,
                label: Translation.tr("Emoji")
            }),
        ({
                prefix: Config.options.search.prefix.action,
                label: Translation.tr("Commands")
            })
    ]

    // The label for whatever scope the query is currently in, empty when the
    // query has no prefix and every provider is answering.
    readonly property string activeScopeLabel: {
        const hit = root.scopeHints.find(scope => root.query.startsWith(scope.prefix));
        return hit ? hit.label : "";
    }

    Component {
        id: resultComp
        LauncherSearchResult {}
    }

    function mathRow(): var {
        return resultComp.createObject(null, {
            key: "math",
            name: root.mathResult,
            verb: Translation.tr("Copy"),
            type: Translation.tr("Math result"),
            fontType: LauncherSearchResult.FontType.Monospace,
            iconName: 'calculate',
            iconType: LauncherSearchResult.IconType.Material,
            execute: () => {
                Quickshell.clipboardText = root.mathResult;
            }
        });
    }

    function commandRow(): var {
        return resultComp.createObject(null, {
            key: "shell",
            name: StringUtils.cleanPrefix(root.query, Config.options.search.prefix.shellCommand).replace("file://", ""),
            verb: Translation.tr("Run"),
            type: Translation.tr("Command"),
            fontType: LauncherSearchResult.FontType.Monospace,
            iconName: 'terminal',
            iconType: LauncherSearchResult.IconType.Material,
            execute: () => {
                let cleanedCommand = root.query.replace("file://", "");
                cleanedCommand = StringUtils.cleanPrefix(cleanedCommand, Config.options.search.prefix.shellCommand);
                if (cleanedCommand.startsWith(Config.options.search.prefix.shellCommand)) {
                    cleanedCommand = cleanedCommand.slice(Config.options.search.prefix.shellCommand.length);
                }
                // query still carries the shell prefix; test what runs
                Quickshell.execDetached(["koompi-launch", "--id", cleanedCommand.trim().split(/\s+/)[0].split("/").pop(), "--", "bash", "-c", cleanedCommand.trim().startsWith('sudo') ? `${Config.options.apps.terminal} fish -C '${cleanedCommand}'` : cleanedCommand]);
            }
        });
    }

    function webRow(): var {
        return resultComp.createObject(null, {
            key: "web",
            name: StringUtils.cleanPrefix(root.query, Config.options.search.prefix.webSearch),
            verb: Translation.tr("Search"),
            type: Translation.tr("Web search"),
            iconName: 'travel_explore',
            iconType: LauncherSearchResult.IconType.Material,
            execute: () => {
                let query = StringUtils.cleanPrefix(root.query, Config.options.search.prefix.webSearch);
                let url = Config.options.search.engineBaseUrl + query;
                for (let site of Config.options.search.excludedSites) {
                    url += ` -site:${site}`;
                }
                Quickshell.execDetached(["koompi-launch", "xdg-open", url]);
            }
        });
    }

    function actionRows(): var {
        return root.allActions.map(action => {
            const actionString = `${Config.options.search.prefix.action}${action.action}`;
            if (!actionString.startsWith(root.query) && !root.query.startsWith(actionString))
                return null;
            return resultComp.createObject(null, {
                key: `action|${action.action}`,
                name: root.query.startsWith(actionString) ? root.query : actionString,
                verb: Translation.tr("Run"),
                type: Translation.tr("Action"),
                iconName: 'settings_suggest',
                iconType: LauncherSearchResult.IconType.Material,
                execute: () => {
                    action.execute(root.query.split(" ").slice(1).join(" "));
                }
            });
        }).filter(Boolean);
    }

    function moreRow(total: int, prefix: string, id: string): var {
        if (prefix === "")
            return null;
        return resultComp.createObject(null, {
            key: `more|${id}`,
            name: Translation.tr("Show all %1").arg(total),
            verb: Translation.tr("Show"),
            iconName: "unfold_more",
            iconType: LauncherSearchResult.IconType.Material,
            keepOpen: true,
            execute: () => root.showScope(prefix)
        });
    }

    // A sigil is a filter: the one provider it names, the way it always listed.
    function scopedResults(): var {
        const prefix = Config.options.search.prefix;
        const clean = sigil => StringUtils.cleanPrefix(root.query, sigil);
        if (root.query.startsWith(prefix.clipboard))
            return root.clipboard.rows(clean(prefix.clipboard));
        if (root.query.startsWith(prefix.emojis))
            return root.clipboard.emojis(clean(prefix.emojis));
        if (root.query.startsWith(prefix.window))
            return root.windows.rows(clean(prefix.window));
        if (root.query.startsWith(prefix.settings))
            return root.settings.rows(clean(prefix.settings));
        if (root.query.startsWith(prefix.file))
            return root.files.scoped(clean(prefix.file));
        if (root.query.startsWith(prefix.action))
            return CommandTree.results(root.query).concat(root.actionRows());
        if (root.query.startsWith(prefix.app))
            return root.apps.matches(clean(prefix.app));
        if (root.query.startsWith(prefix.math))
            return [root.mathRow()];
        if (root.query.startsWith(prefix.shellCommand))
            return [root.commandRow()];
        return [root.webRow()];
    }

    function blendedResults(): var {
        const query = root.query;
        const translateText = Ranking.translateText(query, "translate");
        const startsWithNumber = /^\d/.test(query);
        const math = Ranking.mathWorthShowing(query, root.mathResult) ? root.mathRow() : null;
        if (math && startsWithNumber)
            math.tier = 100;
        const commands = (translateText !== null ? [root.translator.row(translateText)] : []).concat(Ranking.rankRows(CommandTree.blended(query).concat(root.settings.rows(query)), query));
        const found = Ranking.blend({
            query: query,
            topTitle: Translation.tr("Top Hit"),
            pinnedTop: root.pinned.query === query ? root.pinned.key : "",
            makeMore: root.moreRow,
            sections: [
                {
                    id: "apps",
                    title: Translation.tr("Applications"),
                    rows: root.apps.matches(query),
                    top: true,
                    prefix: Config.options.search.prefix.app
                },
                {
                    id: "windows",
                    title: Translation.tr("Windows"),
                    rows: root.windows.rows(query),
                    top: true,
                    prefix: Config.options.search.prefix.window
                },
                {
                    id: "commands",
                    title: Translation.tr("Commands and Settings"),
                    rows: commands,
                    top: true,
                    prefix: Config.options.search.prefix.action
                },
                {
                    id: "files",
                    title: Translation.tr("Files"),
                    rows: Ranking.rankRows(root.files.blended(query), query),
                    top: true,
                    prefix: Config.options.search.prefix.file
                },
                {
                    id: "calc",
                    title: Translation.tr("Calculator"),
                    rows: math ? [math] : [],
                    top: startsWithNumber
                },
                {
                    id: "clipboard",
                    title: Translation.tr("Clipboard"),
                    rows: query.trim().length >= 2 ? root.clipboard.rows(query) : [],
                    cap: 3,
                    prefix: Config.options.search.prefix.clipboard
                }
            ],
            tail: Config.options.search.prefix.showDefaultActionsWithoutPrefix ? [root.commandRow(), root.webRow()] : []
        });
        root.pinned.query = query;
        root.pinned.key = found.topKey;
        return found.rows;
    }

    property list<var> results: {
        if (root.query == "")
            return root.apps.recent();
        if (root.isPlain(root.query))
            return root.blendedResults();
        return root.scopedResults();
    }
}
