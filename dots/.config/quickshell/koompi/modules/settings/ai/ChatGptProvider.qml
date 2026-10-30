import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import "endpoint-form.js" as Form

/**
 * The ChatGPT plan: "Continue with ChatGPT" while signed out, who is signed in,
 * Manage usage and Sign out while signed in, and the models used through the plan
 * (`ai.extraModels` entries with `auth: "chatgpt"`). The sign-in itself is
 * ChatGptAccount, which runs scripts/ai/chatgpt_auth.py.
 */
ColumnLayout {
    id: root

    readonly property var entries: Config.options.ai.extraModels ?? []
    readonly property var planModels: root.entries
        .map((entry, index) => ({ "entry": entry, "index": index }))
        .filter(row => Form.isPlan(row.entry))
    property string addProblem: ""

    readonly property string state: ChatGptAccount.signingIn ? "signing-in"
        : !ChatGptAccount.known ? "unknown"
        : ChatGptAccount.signedIn ? "signed-in" : "signed-out"

    Layout.fillWidth: true
    spacing: 6

    function addModel(text: string) {
        const id = text.trim().toLowerCase();
        if (id.length === 0) return false;
        if (id === "remote" || id === "local" || root.entries.some(entry => Form.idOf(entry) === id)) {
            root.addProblem = Translation.tr("That model is already in the list.");
            return false;
        }
        root.addProblem = "";
        Config.options.ai.extraModels = Form.replaced(root.entries, -1, Form.planEntry(text));
        return true;
    }

    ProviderRow {
        logo: "openai-symbolic.svg"
        title: Translation.tr("ChatGPT plan")
        subtitleIsProblem: ChatGptAccount.problem.length > 0 || (root.state === "signed-in" && !ChatGptAccount.planUsage)
        subtitle: ChatGptAccount.problem.length > 0 ? ChatGptAccount.problem
            : root.state === "signing-in" ? Translation.tr("Finish signing in in your browser.")
            : root.state === "unknown" ? Translation.tr("Checking…")
            : root.state === "signed-out" ? Translation.tr("Use your ChatGPT plan instead of an API key.")
            : !ChatGptAccount.planUsage ? Translation.tr("Signed in as %1, but this sign-in doesn't include plan usage.").arg(ChatGptAccount.email)
            : Translation.tr("Signed in as %1").arg(ChatGptAccount.email)

        RippleButton {
            id: continueButton
            objectName: "continueWithChatGpt"
            visible: root.state === "signed-out"
            implicitHeight: 36
            horizontalPadding: 14
            buttonRadius: Appearance.rounding.full
            colBackground: Appearance.m3colors.m3onSurface
            colBackgroundHover: ColorUtils.mix(Appearance.m3colors.m3onSurface, Appearance.m3colors.m3surface, 0.85)
            colRipple: ColorUtils.mix(Appearance.m3colors.m3onSurface, Appearance.m3colors.m3surface, 0.7)
            Accessible.name: continueLabel.text
            onClicked: ChatGptAccount.signIn()
            contentItem: RowLayout {
                spacing: 8
                CustomIcon {
                    implicitWidth: 18
                    implicitHeight: 18
                    width: 18
                    height: 18
                    source: "openai-symbolic.svg"
                    colorize: true
                    color: Appearance.m3colors.m3surface
                }
                StyledText {
                    id: continueLabel
                    text: Translation.tr("Continue with ChatGPT")
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.Medium
                    color: Appearance.m3colors.m3surface
                }
            }
        }
        RippleButtonWithIcon {
            visible: root.state === "signing-in" && ChatGptAccount.signInUrl.length > 0
            materialIcon: "open_in_new"
            mainText: Translation.tr("Open the page again")
            onClicked: ChatGptAccount.reopenSignInPage()
        }
        RippleButtonWithIcon {
            objectName: "cancelSignIn"
            visible: root.state === "signing-in"
            materialIcon: "close"
            mainText: Translation.tr("Cancel")
            onClicked: ChatGptAccount.cancelSignIn()
        }
        RippleButtonWithIcon {
            // hidden until the destination is known; see ChatGptAccount.manageUsageUrl
            visible: root.state === "signed-in" && ChatGptAccount.manageUsageUrl.length > 0
            materialIcon: "data_usage"
            mainText: Translation.tr("Manage usage")
            onClicked: Qt.openUrlExternally(ChatGptAccount.manageUsageUrl)
        }
        RippleButtonWithIcon {
            objectName: "signOut"
            visible: root.state === "signed-in"
            enabled: !ChatGptAccount.signingOut
            materialIcon: "logout"
            mainText: Translation.tr("Sign out")
            onClicked: ChatGptAccount.signOut()
        }
    }

    // the models the plan answers with; picking one in the chat says "Using ChatGPT plan"
    ColumnLayout {
        Layout.fillWidth: true
        Layout.leftMargin: 34
        visible: root.state === "signed-in" || root.planModels.length > 0
        spacing: 2

        StyledText {
            Layout.fillWidth: true
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            wrapMode: Text.Wrap
            text: root.planModels.length === 0
                ? Translation.tr("Add a model to use it in the chat.")
                : Translation.tr("Models in the chat's model list:")
        }

        Repeater {
            model: root.planModels
            delegate: RowLayout {
                id: planRow
                required property var modelData
                Layout.fillWidth: true
                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    font.family: Appearance.font.family.monospace
                    text: `${planRow.modelData.entry.model}`
                }
                RippleButtonWithIcon {
                    materialIcon: "delete"
                    mainText: Translation.tr("Remove")
                    onClicked: Config.options.ai.extraModels = Form.removed(root.entries, planRow.modelData.index)
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            visible: root.state === "signed-in"
            MaterialTextField {
                id: planModelField
                objectName: "planModelField"
                Layout.fillWidth: true
                placeholderText: Translation.tr("Model id")
                onAccepted: if (root.addModel(text)) text = ""
                onTextChanged: root.addProblem = ""
            }
            RippleButtonWithIcon {
                enabled: planModelField.text.trim().length > 0
                materialIcon: "add"
                mainText: Translation.tr("Add")
                onClicked: if (root.addModel(planModelField.text)) planModelField.text = ""
            }
        }
        StyledText {
            Layout.fillWidth: true
            visible: root.addProblem.length > 0
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colError
            text: root.addProblem
        }
    }
}
