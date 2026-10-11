import qs.services
import qs.modules.common
import QtQuick

GlanceCard {
    id: root
    objectName: "w-upnext"
    cardIcon: "event"
    cardTitle: Translation.tr("Up next")

    readonly property var upcoming: {
        const today = new Date(DateTime.clock.date);
        today.setHours(0, 0, 0, 0);
        const now = DateTime.clock.date.getTime();
        const tomorrow = today.getTime() + 86400000;
        return GoogleCalendar.events
            .filter(e => e.start.getTime() < tomorrow + 86400000 && (e.allDay ? e.start.getTime() >= today.getTime() : e.start.getTime() >= now))
            .sort((a, b) => a.start - b.start)
            .slice(0, 3)
            .map(e => ({
                lead: (e.start.getTime() >= tomorrow ? Translation.tr("tomorrow") + " " : "") + (e.allDay ? Translation.tr("all day") : e.start.toLocaleTimeString(Qt.locale(), "hh:mm")),
                summary: e.summary
            }));
    }

    GlanceLine {
        visible: !GoogleCalendar.connected
        muted: true
        text: Translation.tr("No calendar connected")
    }
    GlanceLine {
        visible: GoogleCalendar.connected && root.upcoming.length === 0
        muted: true
        text: Translation.tr("Nothing today or tomorrow")
    }
    Repeater {
        model: root.upcoming
        delegate: GlanceLine {
            required property var modelData
            lead: modelData.lead
            text: modelData.summary
        }
    }
}
