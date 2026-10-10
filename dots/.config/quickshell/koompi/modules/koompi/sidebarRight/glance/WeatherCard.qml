import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

GlanceCard {
    id: root
    objectName: "w-weather"
    cardIcon: "partly_cloudy_day"
    cardTitle: Translation.tr("Weather")
    interactive: false

    GlanceLine {
        visible: !Config.options.bar.weather.enable
        muted: true
        text: Translation.tr("Weather is off. Turn it on in Settings.")
    }
    Loader {
        Layout.fillWidth: true
        active: Config.options.bar.weather.enable
        visible: active
        sourceComponent: RowLayout {
            spacing: Appearance.spacing.normal
            MaterialSymbol {
                iconSize: 32
                color: Appearance.colors.colOnLayer1
                text: Icons.getWeatherIcon(Weather.data.wCode) ?? "cloud"
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer1
                    text: Weather.data.city + (Weather.data.condition.length > 0 ? ", " + Weather.data.condition : "")
                }
                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    text: Translation.tr("High %1, low %2").arg(Weather.data.high).arg(Weather.data.low)
                }
            }
            StyledText {
                font.pixelSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colOnLayer1
                text: Weather.data.temp
            }
        }
    }
}
