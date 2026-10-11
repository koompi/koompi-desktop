import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland

StyledPopup {
    id: root
    // a hover popup cannot hold a button
    clickToShow: true

    // lua dispatch: a legacy `exec [float]` string errors silently here
    readonly property string runUpdate: "hl.dsp.exec_cmd([==[bash -c '"
        + 'for t in wezterm foot "kitty -1" alacritty konsole kgx uxterm xterm; do '
        + 'command -v "${t%% *}" >/dev/null 2>&1 || continue; '
        + 'exec koompi-launch --id koompi-update --terminal "${TERMINAL:-$t}" -- '
        + 'bash -c "koompi update; read -rsn1 -p \\"Done. Press any key to close.\\""; done; '
        + 'koompi-notify-send "No terminal installed" "Run koompi update from a shell"\''
        + ']==], { float = true, center = true, size = "(monitor_w*0.7) (monitor_h*0.7)" })'

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 4

        StyledPopupHeaderRow {
            icon: "system_update"
            label: Translation.tr("Updates available")
        }

        StyledText {
            color: Appearance.colors.colOnSurfaceVariant
            text: Updates.count === 1
                ? Translation.tr("1 package can be updated")
                : Translation.tr("%1 packages can be updated").arg(Updates.count)
        }

        StyledText {
            visible: Updates.lastChecked !== null
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.small
            text: Updates.lastChecked === null ? "" : Translation.tr("Last checked %1").arg(Qt.locale().toString(Updates.lastChecked, Config.options.time.format))
        }

        RowLayout {
            Layout.topMargin: 6
            spacing: 6

            DialogButton {
                objectName: "updateNow"
                buttonText: Translation.tr("Update now")
                colBackground: Appearance.colors.colPrimary
                colBackgroundHover: Appearance.colors.colPrimaryHover
                colRipple: Appearance.colors.colPrimaryActive
                colText: Appearance.colors.colOnPrimary
                onClicked: {
                    Hyprland.dispatch(root.runUpdate);
                    root.close();
                }
            }

            DialogButton {
                enabled: !Updates.checking
                buttonText: Updates.checking ? Translation.tr("Checking...") : Translation.tr("Check again")
                onClicked: Updates.refresh()
            }
        }
    }
}
