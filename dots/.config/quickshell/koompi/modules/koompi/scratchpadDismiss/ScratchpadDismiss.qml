pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

// Overlay-layer dismiss surface for scratchpad windows. WlrLayer.Overlay sits above
// every window, and a Region with Intersection.Subtract punches a hole so the
// scratchpad stays interactive.
//
// Tradeoff: the first click on the bar or another window closes the scratchpad and
// is consumed. Matches the Super+/ overlay.
Scope {
    id: root

    readonly property var managedSpecials: [
        "special:telegram", "special:discord", "special:whatsapp",
        "special:term", "special:sysmon"
    ]

    // monitorName -> wsName (e.g. "eDP-1" -> "special:telegram")
    property var activeSpecials: ({})

    // Seed state on startup: a scratchpad may already be open
    Process {
        running: true
        command: ["hyprctl", "-j", "monitors"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const monitors = JSON.parse(text)
                    const s = {}
                    for (const m of monitors) {
                        const ws = m.specialWorkspace?.name ?? ""
                        if (ws && root.managedSpecials.includes(ws)) s[m.name] = ws
                    }
                    if (Object.keys(s).length > 0) root.activeSpecials = s
                } catch(e) {}
            }
        }
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name !== "activespecial") return
            const data = event.data
            const sep = data.lastIndexOf(",")
            const wsName = sep >= 0 ? data.slice(0, sep) : ""
            const monName = sep >= 0 ? data.slice(sep + 1) : data
            const s = Object.assign({}, root.activeSpecials)
            if (wsName && root.managedSpecials.includes(wsName)) {
                s[monName] = wsName
            } else {
                delete s[monName]
            }
            root.activeSpecials = s
        }
    }

    Variants {
        model: Quickshell.screens

        LazyLoader {
            id: dismissLoader
            required property ShellScreen modelData

            property HyprlandMonitor monitor: Hyprland.monitorFor(dismissLoader.modelData)
            property string activeWsName: root.activeSpecials[dismissLoader.monitor?.name ?? ""] ?? ""

            active: dismissLoader.activeWsName !== ""

            component: PanelWindow {
                id: dismissWin
                screen: dismissLoader.modelData

                // Scratchpad window rects in monitor-local coordinates, one per client
                // on the special workspace (Telegram opens its call panel as a second
                // toplevel). Empty until real geometry is loaded.
                property var scratchRects: []

                Component {
                    id: holeComponent
                    Region { intersection: Intersection.Subtract }
                }

                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
                WlrLayershell.namespace: "quickshell:scratchpadDismiss"
                exclusionMode: ExclusionMode.Ignore
                color: "transparent"
                anchors { top: true; bottom: true; left: true; right: true }

                // While scratchRects is empty, before geometry loads, a single 9999x9999
                // subtract covers the whole screen and the overlay is fully passthrough.
                mask: Region {
                    width: dismissWin.width
                    height: dismissWin.height
                    regions: (dismissWin.scratchRects.length > 0
                        ? dismissWin.scratchRects
                        : [{ x: 0, y: 0, width: 9999, height: 9999 }]
                    ).map(r => holeComponent.createObject(this, r))
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        const ws = dismissLoader.activeWsName
                        if (ws) Hyprland.dispatch(`hl.dsp.workspace.toggle_special("${ws.replace("special:", "")}")`)
                    }
                }

                Process {
                    id: geomQuery
                    command: ["hyprctl", "-j", "clients"]
                    stdout: StdioCollector {
                        id: geomData
                        onStreamFinished: {
                            try {
                                const clients = JSON.parse(geomData.text)
                                const ws = dismissLoader.activeWsName
                                const mx = dismissLoader.monitor?.x ?? 0
                                const my = dismissLoader.monitor?.y ?? 0
                                // No match leaves the array empty, which is the passthrough fallback
                                dismissWin.scratchRects = clients
                                    .filter(c => c.workspace?.name === ws)
                                    .map(c => ({ x: c.at[0] - mx, y: c.at[1] - my, width: c.size[0], height: c.size[1] }))
                            } catch(e) {}
                        }
                    }
                }

                // Short delay so Hyprland finishes placing the window before we query
                Timer {
                    id: geomTimer
                    interval: 80
                    onTriggered: {
                        geomQuery.running = false
                        geomQuery.running = true
                    }
                }

                Component.onCompleted: geomTimer.start()

                // Re-query if a scratchpad window moves, resizes, opens, closes or
                // toggles floating (a second toplevel such as a call panel changes the mask)
                Connections {
                    target: Hyprland
                    function onRawEvent(event) {
                        if (["movewindow", "movewindowv2", "openwindow", "closewindow", "changefloatingmode"].includes(event.name)) {
                            geomTimer.restart()
                        }
                    }
                }
            }
        }
    }
}
