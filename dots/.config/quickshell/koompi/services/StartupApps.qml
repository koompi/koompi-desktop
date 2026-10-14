pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

/**
 * Keeps apps from putting themselves on login without asking. koompi-startup-apps does the
 * work: a new ~/.config/autostart entry is turned off and its app asked about, Allow or
 * Don't allow. This runs it at startup - asking again about anything left unanswered last
 * session - and then once a minute, so an app that adds itself mid-session is caught before
 * the next login.
 */
Singleton {
    id: root

    function load() {}

    Timer {
        interval: 60000
        running: true
        repeat: true
        triggeredOnStart: true
        property bool first: true
        onTriggered: {
            Quickshell.execDetached(["bash", "-c", 'PATH="$HOME/.local/bin:$PATH" exec koompi-startup-apps scan "$1"', "_", first ? "--remind" : ""]);
            first = false;
        }
    }
}
