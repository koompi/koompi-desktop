import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Settings > AI > Providers: who can answer. The model on this machine is always
 * there; the ChatGPT plan, API keys and custom endpoints are the remote ones, and
 * `policies.ai == 2` (local only) leaves just the first. Keys are written through
 * AiProviders, so nothing here needs the Ai engine to be running.
 */
ContentSection {
    id: root
    icon: "hub"
    title: Translation.tr("Providers")

    readonly property bool remoteAllowed: Config.options.policies.ai !== 2

    ProviderRow {
        icon: "computer"
        title: Translation.tr("On this machine")
        subtitle: Translation.tr("LiteRT-LM, always available. Nothing you type leaves this computer.")
    }

    StyledText {
        Layout.fillWidth: true
        visible: !root.remoteAllowed
        wrapMode: Text.Wrap
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colSubtext
        text: Translation.tr("Online providers are turned off on this computer (policies.ai).")
    }

    ContentSubsection {
        visible: root.remoteAllowed
        ChatGptProvider {}
    }

    ContentSubsection {
        visible: root.remoteAllowed
        title: Translation.tr("API keys")
        tooltip: Translation.tr("Keys are kept in the keyring, never in a file.")
        ApiKeyProviders {}
    }

    ContentSubsection {
        visible: root.remoteAllowed
        title: Translation.tr("Custom endpoints")
        tooltip: Translation.tr("Each one is a model in the chat's model list.")
        CustomEndpoints {}
    }
}
