import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Everything that is on and may be forgotten, each light only while it is on, in
 * one fixed order: recording, microphone in use, mic muted, volume muted, keep
 * awake, night light, Do Not Disturb, dictation. Each is its own hit area; a
 * click turns the mode off or the mute undone, and the lights that only report
 * (recording, mic in use) do nothing.
 */
GridLayout {
    id: root
    // the colours of the surface it is drawn on: the bar's glass may be the other tone (BarScheme)
    readonly property BarScheme barScheme: root.QsWindow.window?.barScheme ?? ownBarScheme
    BarScheme {
        id: ownBarScheme
    }

    property real realSpacing: Appearance.spacing.large
    property color color: root.barScheme.fg
    property bool vertical: false
    readonly property var tooltipEdges: (!Config.options.bar.bottom && !Config.options.bar.vertical) ? Edges.Bottom : Edges.Top

    // Kiri marks a running dictation with $XDG_RUNTIME_DIR/kiri-voice.pid
    // (kiri/src/ui/voice.rs, voice_pid_path). The file outlives a crash, so the
    // pid is checked against /proc before the light goes on. Same 2s poll as
    // ScreenRecording, and paused while locked for the same reason.
    property bool dictating: false

    rowSpacing: 0
    columnSpacing: 0
    columns: root.vertical ? 1 : 16
    // a hidden layout hides its children, so this reads their flags, not its own size
    visible: root.children.some(c => c.reveal)

    Process {
        id: kiriCheck
        command: ["bash", "-c", "read -r pid < \"${XDG_RUNTIME_DIR:-/tmp}/kiri-voice.pid\" && [[ -d /proc/$pid ]]"]
        onExited: exitCode => root.dictating = (exitCode === 0)
    }

    Timer {
        running: PowerSaving.awake
        repeat: true
        interval: PowerSaving.interval(2000)
        triggeredOnStart: true
        onTriggered: if (!kiriCheck.running)
            kiriCheck.running = true
    }

    component ModeIndicator: Revealer {
        id: indicator
        required property string icon
        required property string tooltip
        property var toggle: null
        property bool pulse: false
        property color iconColor: root.color

        vertical: root.vertical
        Layout.alignment: root.vertical ? Qt.AlignHCenter : Qt.AlignVCenter
        Layout.rightMargin: (reveal && !root.vertical) ? root.realSpacing : 0
        Layout.bottomMargin: (reveal && root.vertical) ? root.realSpacing : 0
        Behavior on Layout.rightMargin {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        Behavior on Layout.bottomMargin {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        MaterialSymbol {
            text: indicator.icon
            iconSize: Appearance.font.pixelSize.larger
            color: indicator.iconColor

            // A light that does not move reads as an icon.
            SequentialAnimation on opacity {
                running: indicator.pulse && indicator.reveal && !Appearance.reduceMotion
                loops: Animation.Infinite
                NumberAnimation { to: 0.35; duration: 700; easing.type: Easing.InOutQuad }
                NumberAnimation { to: 1.0; duration: 700; easing.type: Easing.InOutQuad }
            }

            MouseArea {
                id: indicatorHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: indicator.toggle ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: if (indicator.toggle) indicator.toggle()
            }
            PopupToolTip {
                extraVisibleCondition: indicatorHover.containsMouse
                anchorEdges: root.tooltipEdges
                text: indicator.tooltip
            }
        }
    }

    ModeIndicator {
        objectName: "modeRecording"
        reveal: ScreenRecording.active
        icon: "screen_record"
        iconColor: Appearance.m3colors.m3error
        pulse: true
        tooltip: Translation.tr("Screen recording is on. Click to stop")
        // record.sh stops a running recording itself
        toggle: () => Quickshell.execDetached([Directories.recordScriptPath])
    }
    ModeIndicator {
        objectName: "modeMicInUse"
        reveal: Privacy.micActive && !root.dictating
        icon: "mic"
        tooltip: Translation.tr("An app is using the microphone. Click for sound settings")
        toggle: () => GlobalStates.toggleSidebarRightOn("sound")
    }
    ModeIndicator {
        objectName: "modeMicMuted"
        reveal: Audio.source?.audio?.muted ?? false
        icon: "mic_off"
        tooltip: Translation.tr("Microphone is muted. Click to unmute")
        toggle: () => Audio.toggleMicMute()
    }
    ModeIndicator {
        objectName: "modeVolumeMuted"
        reveal: Audio.sink?.audio?.muted ?? false
        icon: "volume_off"
        tooltip: Translation.tr("Sound is muted. Click to unmute")
        toggle: () => Audio.toggleMute()
    }
    ModeIndicator {
        objectName: "modeKeepAwake"
        reveal: Idle.inhibit
        icon: "coffee"
        tooltip: Translation.tr("Keep awake is on. Click to turn it off")
        toggle: () => Idle.toggleInhibit()
    }
    ModeIndicator {
        objectName: "modeNightLight"
        reveal: Hyprsunset.temperatureActive
        icon: "bedtime"
        tooltip: Translation.tr("Night light is on. Click to turn it off")
        toggle: () => Hyprsunset.toggleTemperature()
    }
    ModeIndicator {
        objectName: "modeDoNotDisturb"
        reveal: Notifications.silent
        icon: "do_not_disturb_on"
        tooltip: Translation.tr("Do Not Disturb is on. Click to turn it off")
        toggle: () => Notifications.silent = false
    }
    ModeIndicator {
        objectName: "modeDictation"
        reveal: root.dictating
        icon: "mic"
        // A live microphone is a recording; same colour as the recording light.
        iconColor: Appearance.m3colors.m3error
        tooltip: Translation.tr("Kiri is listening. Click to stop and paste")
        // What the hotkey does when pressed again: stop, transcribe, paste.
        toggle: () => Quickshell.execDetached(["kiri", "voice"])
    }
}
