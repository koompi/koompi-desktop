import qs.services
import qs.modules.common
import qs.modules.common.models
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * "translate <text>" in Search. The same `trans -brief` call the left sidebar's
 * tab makes, with the engine and languages from language.translator. It is
 * online: the text leaves the machine, and the row says so.
 *
 * One process per settled query (the timer), never per keystroke. With no text
 * the primary selection is read, and only when the row is invoked.
 */
Scope {
    id: root

    readonly property var settings: Config.options.language.translator
    readonly property int delay: 500

    property string requested: ""
    property string translated: ""
    property string translatedFor: ""
    property bool failed: false
    property bool copyWhenDone: false

    readonly property Component rowComp: Component {
        LauncherSearchResult {}
    }

    function argv(text: string): var {
        const flags = [];
        if (root.settings.engine && root.settings.engine !== "auto")
            flags.push("-engine", root.settings.engine);
        if (root.settings.sourceLanguage && root.settings.sourceLanguage !== "auto")
            flags.push("-source", root.settings.sourceLanguage);
        if (root.settings.targetLanguage && root.settings.targetLanguage !== "auto")
            flags.push("-target", root.settings.targetLanguage);
        return ["trans", "-brief", "-no-bidi", ...flags, text];
    }

    function request(text: string) {
        root.requested = text;
        if (text === "") {
            delayTimer.stop();
            transProc.running = false;
            return;
        }
        delayTimer.restart();
    }

    function run(text: string) {
        transProc.running = false;
        transProc.text = text;
        root.translated = "";
        transProc.command = root.argv(text);
        transProc.running = true;
    }

    function translateSelection() {
        selectionProc.running = true;
    }

    Timer {
        id: delayTimer
        interval: root.delay
        onTriggered: root.run(root.requested)
    }

    Process {
        id: transProc
        property string text: ""
        // an empty stdout is a failure whatever the exit code: trans prints its errors to stderr
        stdout: StdioCollector {
            onStreamFinished: {
                root.translated = text.trim();
                root.translatedFor = transProc.text;
                root.failed = root.translated === "";
                if (root.copyWhenDone && !root.failed) {
                    Quickshell.clipboardText = root.translated;
                    Quickshell.execDetached(["notify-send", Translation.tr("Translated, copied"), root.translated, "-a", "Shell"]);
                }
                root.copyWhenDone = false;
            }
        }
    }

    Process {
        id: selectionProc
        command: ["wl-paste", "--primary", "--no-newline"]
        stdout: StdioCollector {
            onStreamFinished: {
                const selected = text.trim();
                if (selected === "")
                    return;
                root.copyWhenDone = true;
                root.run(selected);
            }
        }
    }

    readonly property string online: Translation.tr("Sent to an online translator")

    function row(text: string): var {
        if (text === "") {
            return root.rowComp.createObject(null, {
                key: "translate|selection",
                tier: 100,
                name: Translation.tr("Translate the selected text"),
                type: root.online,
                verb: Translation.tr("Translate"),
                iconName: "translate",
                iconType: LauncherSearchResult.IconType.Material,
                scopePrefix: "",
                execute: () => root.translateSelection()
            });
        }
        const ready = root.translatedFor === text && !root.failed && root.translated !== "";
        const failed = root.translatedFor === text && root.failed;
        return root.rowComp.createObject(null, {
            key: "translate|text",
            tier: 100,
            name: ready ? root.translated : failed ? Translation.tr("Could not translate this") : Translation.tr("Translating..."),
            type: root.online,
            verb: ready ? Translation.tr("Copy") : "",
            iconName: "translate",
            iconType: LauncherSearchResult.IconType.Material,
            execute: () => {
                if (ready)
                    Quickshell.clipboardText = root.translated;
            }
        });
    }
}
