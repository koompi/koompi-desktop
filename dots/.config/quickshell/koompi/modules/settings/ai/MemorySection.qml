import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// Settings > AI > Memory: the daemon, recall, embeddings, and when a conversation is summarised.
ContentSection {
    icon: "database"
    title: Translation.tr("Memory")

    ConfigSwitch {
        buttonIcon: "database"
        text: Translation.tr("Remember things between sessions")
        checked: Config.options.ai.memory.enable
        onCheckedChanged: {
            Config.options.ai.memory.enable = checked;
        }
        StyledToolTip {
            text: Translation.tr("Needs koompi-agent-memd in ~/.local/bin.\nThe installer builds it; without it the assistant forgets everything at logout.")
        }
    }
    ConfigSwitch {
        enabled: Config.options.ai.memory.enable
        buttonIcon: "search_insights"
        text: Translation.tr("Look things up before every reply")
        checked: Config.options.ai.memory.autoRecall
        onCheckedChanged: {
            Config.options.ai.memory.autoRecall = checked;
        }
    }

    ContentSubsection {
        title: Translation.tr("Recall")
        tooltip: Translation.tr("Past the budget the turn is sent without the recall rather than made to wait for it.")

        ConfigRow {
            uniform: true
            enabled: Config.options.ai.memory.enable
            ConfigSpinBox {
                icon: "format_list_numbered"
                text: Translation.tr("Memories recalled")
                value: Config.options.ai.memory.recallCount
                from: 0
                to: 20
                stepSize: 1
                onValueChanged: {
                    Config.options.ai.memory.recallCount = value;
                }
            }
            ConfigSpinBox {
                icon: "hourglass_top"
                text: Translation.tr("Wait for them (ms)")
                value: Config.options.ai.memory.recallBudgetMs
                from: 1
                to: 5000
                stepSize: 100
                onValueChanged: {
                    Config.options.ai.memory.recallBudgetMs = value;
                }
            }
        }
    }

    ContentSubsection {
        title: Translation.tr("Embeddings")
        tooltip: Translation.tr("Local keeps every memory on this machine. The other two send the text to be embedded away.")

        ConfigSelectionArray {
            currentValue: Config.options.ai.memory.provider
            onSelected: newValue => {
                Config.options.ai.memory.provider = newValue;
            }
            options: [
                {
                    displayName: Translation.tr("On this machine"),
                    icon: "sync_saved_locally",
                    value: "local"
                },
                {
                    displayName: Translation.tr("Gemini"),
                    value: "gemini"
                },
                {
                    displayName: Translation.tr("OpenAI"),
                    value: "openai"
                }
            ]
        }
        MaterialTextArea {
            Layout.fillWidth: true
            visible: Config.options.ai.memory.provider !== "local"
            placeholderText: Translation.tr("Keyring id for the embedding key")
            text: Config.options.ai.memory.keyId
            onTextChanged: Config.options.ai.memory.keyId = text
        }
        MaterialTextArea {
            Layout.fillWidth: true
            placeholderText: Translation.tr("Daemon path (blank for ~/.local/bin/koompi-agent-memd)")
            text: Config.options.ai.memory.binary
            onTextChanged: Config.options.ai.memory.binary = text
        }
    }

    ContentSubsection {
        title: Translation.tr("Context and summarising")
        tooltip: Translation.tr("The window is read from the server where it says so, and these are the fallback and the fraction of it a conversation may fill before it is summarised.")

        ConfigRow {
            uniform: true
            ConfigSpinBox {
                icon: "width_wide"
                text: Translation.tr("Context window (0 = ask the server)")
                value: Config.options.ai.memory.contextWindow
                from: 0
                to: 1000000
                stepSize: 1024
                onValueChanged: {
                    Config.options.ai.memory.contextWindow = value;
                }
            }
            ConfigSpinBox {
                icon: "compress"
                text: Translation.tr("Summarise past (0 = derive)")
                value: Config.options.ai.memory.compactionThreshold
                from: 0
                to: 1000000
                stepSize: 1000
                onValueChanged: {
                    Config.options.ai.memory.compactionThreshold = value;
                }
            }
        }
        ConfigSlider {
            buttonIcon: "percent"
            text: Translation.tr("Fraction of the window")
            value: Config.options.ai.memory.compactionFraction
            from: 0.1
            to: 0.95
            onValueChanged: {
                Config.options.ai.memory.compactionFraction = value;
            }
        }
        ConfigSpinBox {
            icon: "lan"
            text: Translation.tr("LiteRT-LM port")
            value: Config.options.ai.memory.litertPort
            from: 1
            to: 65535
            stepSize: 1
            onValueChanged: {
                Config.options.ai.memory.litertPort = value;
            }
        }
    }
}
