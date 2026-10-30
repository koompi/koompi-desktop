import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * The providers ModelRegistry already knows by model name, each with its key.
 * `providers` mirrors the key ids of ModelRegistry.providers (tests/test_ai_providers.sh
 * keeps the two in step); the names are the providers' own and are not translated.
 */
ColumnLayout {
    id: root

    // the keyring answered; until then no key can be read or written
    readonly property bool ready: AiProviders.ready
    // past this the keyring is taken to be locked rather than slow
    property bool waited: false

    readonly property var providers: [
        { "keyId": "openai", "name": "OpenAI", "logo": "openai-symbolic.svg", "link": "" },
        { "keyId": "gemini", "name": "Google Gemini", "logo": "google-gemini-symbolic.svg", "link": "" },
        { "keyId": "mistral", "name": "Mistral", "logo": "mistral-symbolic.svg", "link": "" },
        { "keyId": "openrouter", "name": "OpenRouter", "logo": "openrouter-symbolic.svg", "link": "" },
        { "keyId": "deepseek", "name": "DeepSeek", "logo": "deepseek-symbolic.svg", "link": "" },
        { "keyId": "moonshot", "name": "Moonshot (Kimi)", "logo": "spark-symbolic.svg", "link": "" },
        { "keyId": "zai", "name": "Z.ai (GLM)", "logo": "spark-symbolic.svg", "link": "" },
        { "keyId": "minimax", "name": "MiniMax", "logo": "spark-symbolic.svg", "link": "" },
        { "keyId": "oxalpha", "name": "0xAlpha", "logo": "oxalpha-symbolic.svg", "link": "https://oxalpha.io/ox-alpha-api.html" },
    ]

    Layout.fillWidth: true
    spacing: 8

    function fetch() {
        root.waited = false;
        lockedTimer.restart();
        AiProviders.fetch();
    }

    Timer {
        id: lockedTimer
        interval: 4000
        onTriggered: root.waited = true
    }

    Component.onCompleted: if (!root.ready) root.fetch()

    RowLayout {
        Layout.fillWidth: true
        visible: !root.ready
        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: root.waited ? Appearance.colors.colError : Appearance.colors.colSubtext
            text: root.waited
                ? Translation.tr("The keyring is locked, so keys can't be read or changed. Unlock it, then try again.")
                : Translation.tr("Reading the keyring…")
        }
        RippleButtonWithIcon {
            visible: root.waited
            materialIcon: "refresh"
            mainText: Translation.tr("Try again")
            onClicked: root.fetch()
        }
    }

    Repeater {
        model: root.providers
        delegate: ApiKeyRow {
            required property var modelData
            ready: root.ready
            keyId: modelData.keyId
            title: modelData.name
            logo: modelData.logo
            keyLink: modelData.link
        }
    }
}
