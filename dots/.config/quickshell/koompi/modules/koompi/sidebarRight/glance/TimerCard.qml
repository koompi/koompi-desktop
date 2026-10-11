import qs.services
import qs.modules.common
import QtQuick

GlanceCard {
    id: root
    objectName: "w-timer"
    cardIcon: "schedule"
    cardTitle: Translation.tr("Timer")

    function clock(seconds) {
        const s = Math.max(0, Math.round(seconds));
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0");
    }

    GlanceLine {
        visible: !TimerService.pomodoroRunning && !TimerService.stopwatchRunning
        muted: true
        text: Translation.tr("Start a timer")
    }
    GlanceLine {
        visible: TimerService.pomodoroRunning
        lead: TimerService.pomodoroBreak ? Translation.tr("Break") : Translation.tr("Focus")
        text: root.clock(TimerService.pomodoroSecondsLeft)
    }
    GlanceLine {
        visible: TimerService.stopwatchRunning && !TimerService.pomodoroRunning
        lead: Translation.tr("Stopwatch")
        text: root.clock(TimerService.stopwatchTime / 100)
    }
}
