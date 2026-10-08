import QtQuick
import Quickshell

// A surface that exists only while it is wanted.
//   LazySurface { open: GlobalStates.thingOpen; component: PanelWindow { visible: GlobalStates.thingOpen } }
// open      wanted; turning it on builds `component` in that call, so `item` works on the next line
// keepWarm  ms the instance outlives `open`, so open-close-open inside it is one instance; 0 releases at once
// item      what `component` built, null while released; outside the component reach the window as `surface.item?.hide()`
// The window keeps its own `visible`, keyboard focus and GlobalFocusGrab bindings, and does its just-opened work
// in Component.onCompleted too: a fresh instance never saw the flag change.
// IpcHandler, GlobalShortcut and state stay in the always-built Scope beside this, so keys and IPC work with no window.
LazyLoader {
    id: root

    property bool open: false
    property int keepWarm: 120000

    // set before `open` can turn off, so `active` never sees both false while the surface is warm
    property bool _held: false
    // named, or LazyLoader's `component` default property swallows it
    property Timer _release: Timer {
        interval: root.keepWarm
        onTriggered: root._held = false
    }

    active: root.open || root._held

    onOpenChanged: {
        if (root.open) {
            root._held = true;
            root._release.stop();
        } else if (root.keepWarm > 0) {
            root._release.restart();
        } else {
            root._held = false;
        }
    }
}
