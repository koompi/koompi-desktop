import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: true

    property var hyprMonitors: ({})
    property var pending: null
    property var failure: null
    property int busy: 0
    property real clock: Date.now() / 1000
    readonly property int secondsLeft: root.pending ? Math.max(0, Math.ceil(root.pending.deadline - root.clock)) : 0
    // groups stay enabled so the running rate keeps its selected look; clicks are ignored instead
    readonly property bool locked: root.pending !== null || root.busy > 0
    readonly property string anchorName: {
        const screens = [...Quickshell.screens];
        return (screens.find(s => s.name?.startsWith("eDP")) ?? screens[0])?.name ?? "";
    }
    // absolute path: the session env may lack ~/.local/bin on PATH
    readonly property string displaysTool: Quickshell.env("HOME") + "/.local/bin/koompi-displays"

    function ratesAtCurrentSize(info) {
        if (!info?.availableModes) return [];
        const prefix = `${info.width}x${info.height}@`;
        const seen = {};
        for (const mode of info.availableModes) {
            if (!mode.startsWith(prefix)) continue;
            const rate = Math.round(parseFloat(mode.slice(prefix.length)) * 100) / 100;
            if (rate > 0) seen[rate] = true;
        }
        return Object.keys(seen).map(Number).sort((a, b) => b - a);
    }

    function currentRateOf(rates, info) {
        const now = info?.refreshRate ?? 0;
        const nearest = [...rates].sort((a, b) => Math.abs(a - now) - Math.abs(b - now))[0];
        return nearest !== undefined && Math.abs(nearest - now) < 0.05 ? nearest : null;
    }

    function rateText(rate, rates) {
        const clash = rates.some(other => other !== rate && Math.round(other) === Math.round(rate));
        return String(clash ? rate : Math.round(rate));
    }

    function rateLabel(rate, rates) {
        return Translation.tr("%1 Hz").arg(root.rateText(rate, rates));
    }

    function run(row, args) {
        root.busy++;
        root.failure = null;
        commandFactory.createObject(root, { row: row, args: args });
    }

    function answer(verb) {
        if (!root.pending || root.busy > 0) return;
        root.run(`${root.pending.monitor}/rate`, [verb]);
    }

    function messageOf(text) {
        const message = text.split("\n").map(line => line.replace(/^koompi-displays:\s*/, "")).join(" ").trim()
            || Translation.tr("The display tool did not run");
        return message.charAt(0).toUpperCase() + message.slice(1);
    }

    // read now so the pills match the monitor, and again once a rewritten monitors.lua has been applied
    function refreshMonitors() {
        monitorsProc.running = false;
        monitorsProc.running = true;
        monitorsRefreshTimer.restart();
    }

    function commandFinished(row, verb, code, out, err) {
        root.busy--;
        if (code !== 0)
            root.failure = { row: row, message: root.messageOf(err || out) };
        if (verb === "rate" && code === 0) {
            root.clock = Date.now() / 1000;
            root.pending = JSON.parse(out);
        } else if (verb === "keep" || verb === "revert") {
            root.pending = null;
        }
        root.refreshMonitors();
    }

    Component.onCompleted: {
        Hyprsunset.fetchState();
    }

    Component.onDestruction: {
        if (root.pending)
            Quickshell.execDetached([root.displaysTool, "revert"]);
    }

    component RowError: StyledText {
        visible: text !== ""
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colError
    }

    Component {
        id: commandFactory
        DisplaysCommand {
            tool: root.displaysTool
            onFinished: (code, out, err) => root.commandFinished(row, args[0], code, out, err)
        }
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.pending !== null
        onTriggered: {
            root.clock = Date.now() / 1000;
            if (root.secondsLeft === 0)
                root.answer("revert");
        }
    }

    Timer {
        id: monitorsRefreshTimer
        interval: 1200
        onTriggered: {
            monitorsProc.running = false;
            monitorsProc.running = true;
        }
    }

    Process {
        id: monitorsProc
        running: true
        command: ["hyprctl", "-j", "monitors"]
        stdout: StdioCollector {
            id: monitorsCollector
            onStreamFinished: {
                const parsed = JSON.parse(monitorsCollector.text);
                const map = {};
                for (const monitor of parsed) map[monitor.name] = monitor;
                root.hyprMonitors = map;
            }
        }
    }

    ContentSection {
        icon: "monitor"
        title: Translation.tr("Monitors")

        StyledText {
            visible: Quickshell.screens.length === 0
            text: Translation.tr("No monitors found")
            color: Appearance.colors.colSubtext
        }

        Repeater {
            model: ScriptModel {
                values: [...Quickshell.screens]
            }
            delegate: ColumnLayout {
                id: monitorBlock
                required property var modelData
                readonly property var screenInfo: monitorBlock.modelData
                readonly property string monitorName: monitorBlock.screenInfo?.name ?? ""
                readonly property var hyprInfo: root.hyprMonitors[monitorBlock.monitorName]
                readonly property var brightnessMonitor: Brightness.getMonitorForScreen(monitorBlock.screenInfo)
                readonly property var refreshRates: root.ratesAtCurrentSize(monitorBlock.hyprInfo)
                readonly property var currentRate: root.currentRateOf(monitorBlock.refreshRates, monitorBlock.hyprInfo)
                readonly property bool waiting: root.pending?.monitor === monitorBlock.monitorName
                readonly property string relativePosition: {
                    const a = root.hyprMonitors[root.anchorName];
                    const m = monitorBlock.hyprInfo;
                    if (!a || !m) return "";
                    if (m.x + m.width / m.scale <= a.x) return "left";
                    if (m.x >= a.x + a.width / a.scale) return "right";
                    if (m.y < a.y) return "above";
                    return "below";
                }

                spacing: 4
                Layout.fillWidth: true

                ConfigRow {
                    MaterialSymbol {
                        text: "monitor"
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnLayer1
                    }
                    ColumnLayout {
                        spacing: 0
                        Layout.fillWidth: true
                        StyledText {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            textFormat: Text.PlainText
                            text: {
                                const name = monitorBlock.screenInfo?.name ?? Translation.tr("Unknown monitor");
                                const model = monitorBlock.screenInfo?.model;
                                return model ? `${name} • ${model}` : name;
                            }
                        }
                        StyledText {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                            text: {
                                const details = [];
                                const width = monitorBlock.screenInfo?.width ?? 0;
                                const height = monitorBlock.screenInfo?.height ?? 0;
                                const refreshRate = monitorBlock.hyprInfo?.refreshRate;
                                const rate = monitorBlock.currentRate !== null
                                    ? root.rateText(monitorBlock.currentRate, monitorBlock.refreshRates)
                                    : Math.round(refreshRate * 100) / 100;
                                details.push(refreshRate !== undefined ? `${width}x${height}@${rate}Hz` : `${width}x${height}`);
                                const scale = monitorBlock.hyprInfo?.scale;
                                if (scale !== undefined)
                                    details.push(Translation.tr("Scale %1").arg(scale));
                                const x = monitorBlock.hyprInfo?.x;
                                const y = monitorBlock.hyprInfo?.y;
                                if (x !== undefined && y !== undefined)
                                    details.push(Translation.tr("Position %1, %2").arg(x).arg(y));
                                return details.join(" • ");
                            }
                        }
                    }
                }
                ConfigSlider {
                    text: Translation.tr("Brightness")
                    buttonIcon: "brightness_6"
                    from: 0
                    to: 1
                    value: monitorBlock.brightnessMonitor?.brightness ?? 0
                    onValueChanged: {
                        monitorBlock.brightnessMonitor?.setBrightness(value);
                    }
                }
                StyledText {
                    visible: monitorBlock.brightnessMonitor?.isDdc ?? false
                    Layout.leftMargin: 8
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    text: Translation.tr("External monitor controlled via DDC/CI")
                }
                ContentSubsection {
                    visible: monitorBlock.refreshRates.length > 1
                    title: Translation.tr("Refresh rate")
                    ConfigSelectionArray {
                        currentValue: monitorBlock.waiting ? root.pending.rate : monitorBlock.currentRate
                        options: monitorBlock.refreshRates.map(rate => ({ displayName: root.rateLabel(rate, monitorBlock.refreshRates), value: rate }))
                        onSelected: newValue => {
                            if (!root.locked && newValue !== monitorBlock.currentRate)
                                root.run(`${monitorBlock.monitorName}/rate`, ["rate", monitorBlock.monitorName, String(newValue)]);
                        }
                    }
                    NoticeBox {
                        visible: monitorBlock.waiting
                        Layout.fillWidth: true
                        materialIcon: "schedule"
                        text: "<b>" + Translation.tr("Keep this refresh rate?") + "</b><br>"
                            + Translation.tr("%1 now. Going back to %2 in %3 s")
                                .arg(root.rateLabel(root.pending?.rate ?? 0, monitorBlock.refreshRates))
                                .arg(root.rateLabel(root.pending?.previous ?? 0, monitorBlock.refreshRates))
                                .arg(root.secondsLeft)
                        RippleButtonWithIcon {
                            materialIcon: "check"
                            mainText: Translation.tr("Keep")
                            onClicked: root.answer("keep")
                        }
                        RippleButtonWithIcon {
                            materialIcon: "undo"
                            mainText: Translation.tr("Revert")
                            onClicked: root.answer("revert")
                        }
                    }
                    RowError { text: root.failure?.row === `${monitorBlock.monitorName}/rate` ? root.failure.message : "" }
                }
                ContentSubsection {
                    visible: monitorBlock.monitorName !== root.anchorName && [...Quickshell.screens].length > 1
                    title: Translation.tr("Position relative to %1").arg(root.anchorName)
                    ConfigSelectionArray {
                        currentValue: monitorBlock.relativePosition
                        options: [
                            { displayName: Translation.tr("Left of"), icon: "arrow_back", value: "left" },
                            { displayName: Translation.tr("Right of"), icon: "arrow_forward", value: "right" },
                            { displayName: Translation.tr("Above"), icon: "arrow_upward", value: "above" },
                            { displayName: Translation.tr("Below"), icon: "arrow_downward", value: "below" }
                        ]
                        onSelected: newValue => {
                            if (!root.locked)
                                root.run(`${monitorBlock.monitorName}/place`, ["place", monitorBlock.monitorName, newValue]);
                        }
                    }
                    RowError { text: root.failure?.row === `${monitorBlock.monitorName}/place` ? root.failure.message : "" }
                }
            }
        }
    }

    ContentSection {
        icon: "nightlight"
        title: Translation.tr("Night light")

        ConfigSwitch {
            buttonIcon: "bedtime"
            text: Translation.tr("Enable night light")
            checked: Hyprsunset.temperatureActive
            onCheckedChanged: {
                if (checked !== Hyprsunset.temperatureActive)
                    Hyprsunset.toggleTemperature(checked);
            }
        }
        ConfigSwitch {
            buttonIcon: "night_sight_auto"
            text: Translation.tr("Automatic schedule")
            checked: Config.options?.light?.night?.automatic ?? false
            onCheckedChanged: {
                Config.options.light.night.automatic = checked;
            }
        }
        ConfigSlider {
            text: Translation.tr("Color temperature")
            buttonIcon: "thermostat"
            usePercentTooltip: false
            from: 1000
            to: 6500
            value: Config.options?.light?.night?.colorTemperature ?? 5000
            onValueChanged: {
                Config.options.light.night.colorTemperature = Math.round(value);
            }
        }
        ConfigSlider {
            text: Translation.tr("Gamma")
            buttonIcon: "brightness_medium"
            from: Hyprsunset.gammaLowerLimit
            to: 100
            value: Hyprsunset.gamma
            onValueChanged: {
                if (Math.round(value) !== Hyprsunset.gamma)
                    Hyprsunset.setGamma(Math.round(value));
            }
        }
    }
}
