pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

// One level of the global menu. A submenu loads this same file again through a
// Loader, because QML refuses to instantiate a type inside itself.
// A layer, not a popup of the bar: Hyprland blurs a popup live, through the window
// under it, and a layer from the wallpaper alone, as it blurs the bar. Only a layer
// can be cut from the bar's own glass.
PanelWindow {
    id: popup

    required property var menu // the GlobalMenu root: daemon channel + patches
    required property Item anchorItem
    /// The bar window the chain hangs from. A submenu's anchor is an entry of the
    /// level above, so the level above hands it down.
    property var bar: popup.anchorItem.QsWindow.window
    /// Set for a submenu: the item whose children this popup shows.
    property var parentEntry: null
    /// Set for the top level: the entries to show.
    property var rootEntries: []
    property bool submenu: false
    property int highlight: -1

    readonly property var entries: popup.parentEntry ? popup.menu.childrenOf(popup.parentEntry) : popup.rootEntries

    signal dismissed // an entry was activated: tear the whole chain down

    BarScheme {
        id: ownScheme
    }
    // the bar's tone: over glass of the other tone, dark text on light glass (BarScheme)
    readonly property BarScheme scheme: popup.bar?.barScheme ?? ownScheme

    // A piece of the bar's glass, tone and tint. Its text needs that tint over the
    // wallpaper under the menu as well, which can be brighter or darker than the strip
    // under the bar, so the tint rises from the bar's to what that band asks, up to
    // solid. A solid bar gives its own colour; a bar drawn with no background still
    // gives its menus one.
    readonly property color surface: {
        const glass = popup.bar?.barGlass ?? null;
        if (!glass) {
            const solid = popup.bar ? popup.bar.barSurface : Appearance.colors.colBarBackground;
            return solid.a > 0 ? solid : Appearance.colors.colBarBackground;
        }
        const height = popup.screen?.height || 1;
        const tiles = BarTone.under(popup.bar.barWallpaper, popup.placedY / height, (popup.placedY + popup.implicitHeight) / height);
        return ColorUtils.applyAlpha(popup.scheme.glass, tiles ? popup.scheme.tintOver(tiles, glass.tint) : 1);
    }

    readonly property real visibleGap: 5
    /// Attached: no gap, and no rounding on the edge shared with the bar. The other bar
    /// popups float clear of it and should keep doing so.
    readonly property bool attachedToBar: !popup.submenu
    readonly property bool growsUp: popup.attachedToBar && Config.options.bar.bottom
    /// The anchor on the screen, taken as the menu opens (mapToItem is not tracked, and
    /// nothing under an open menu moves). The bar spans its screen from the top edge or
    /// the bottom one, and a level above says where it was placed.
    readonly property rect anchorRect: {
        const host = popup.anchorItem.QsWindow.window;
        const at = popup.anchorItem.mapToItem(null, 0, 0);
        const x = popup.submenu ? host.placedX : 0;
        const y = popup.submenu ? host.placedY : popup.growsUp ? (popup.screen?.height ?? 0) - host.height : 0;
        return Qt.rect(x + at.x, y + at.y, popup.anchorItem.width, popup.anchorItem.height);
    }
    // The top level starts at its title's hit target, 10px left of the text, and flush
    // with the bar's edge; a submenu sits beside its entry, and turns to the left of it
    // where the screen ends on the right.
    readonly property int placedX: {
        const r = popup.anchorRect, w = popup.implicitWidth, right = popup.bar?.width ?? 0;
        if (!popup.submenu)
            return Math.round(Math.max(0, Math.min(r.x, right - w)));
        const after = r.x + r.width + popup.visibleGap;
        return Math.round(after + w <= right || r.x - popup.visibleGap - w < 0 ? after : r.x - popup.visibleGap - w);
    }
    readonly property int placedY: {
        const r = popup.anchorRect, h = popup.implicitHeight;
        if (popup.attachedToBar)
            return Math.round(popup.growsUp ? r.y - h : r.y + r.height);
        return Math.round(Math.max(0, Math.min(r.y, (popup.screen?.height ?? 0) - h)));
    }
    readonly property bool turned: popup.placedX < popup.anchorRect.x

    screen: popup.bar?.screen ?? null
    anchors {
        left: true
        top: true
    }
    margins {
        left: popup.placedX
        top: popup.placedY
    }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "quickshell:barMenu"
    WlrLayershell.layer: WlrLayer.Overlay
    // OnDemand, as the bar's other popups: Exclusive breaks click-outside-to-close
    WlrLayershell.keyboardFocus: popup.menu.menuOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    color: "transparent"

    // The border row on the edge shared with the bar falls outside the surface, so it is
    // never drawn across the seam. The other three sides stay: a menu can sit over a
    // window of its own colour.
    implicitWidth: background.implicitWidth
    implicitHeight: background.implicitHeight - (popup.attachedToBar ? 1 : 0)

    function activate(entry) {
        if (!entry || entry.sep || !entry.enabled)
            return;
        popup.menu.send("activate " + entry.id);
        popup.dismissed();
    }

    function moveHighlight(step) {
        const count = popup.entries.length;
        if (count === 0)
            return;
        let i = popup.highlight;
        for (let n = 0; n < count; n++) {
            i = (i + step + count) % count;
            const entry = popup.entries[i];
            if (!entry.sep && entry.enabled) {
                popup.highlight = i;
                return;
            }
        }
    }

    // The bar owns the focus grab for the whole chain and routes keys here; the
    // deepest open popup is the one that answers.
    function handleKey(key) {
        if (childLoader.item && childLoader.item.handleKey(key))
            return true;
        if (key === Qt.Key_Up) {
            popup.moveHighlight(-1);
            return true;
        }
        if (key === Qt.Key_Down) {
            popup.moveHighlight(1);
            return true;
        }
        if (key === Qt.Key_Return || key === Qt.Key_Enter) {
            // Nothing highlighted here (a submenu opened by hover, say) means
            // this level cannot answer; let an outer level try.
            const entry = popup.highlight >= 0 ? popup.entries[popup.highlight] : null;
            if (!entry)
                return false;
            if (popup.menu.hasChildrenFor(entry))
                return popup.openHighlightedChild();
            popup.activate(entry);
            return true;
        }
        return false;
    }

    /// Closes the innermost open submenu. Returns false once this popup is the
    /// innermost one, which is how Escape and Left know to leave the level.
    function closeDeepestChild() {
        if (childLoader.item && childLoader.item.closeDeepestChild())
            return true;
        if (!popup.childEntry)
            return false;
        popup.closeChild();
        return true;
    }

    /// Opens the highlighted entry's submenu in the innermost open popup.
    function openHighlightedChild() {
        if (childLoader.item && childLoader.item.openHighlightedChild())
            return true;
        if (popup.childEntry || popup.highlight < 0)
            return false;
        const entry = popup.entries[popup.highlight];
        if (!entry || !popup.menu.hasChildrenFor(entry))
            return false;
        const item = popup.entryItemAt(popup.highlight);
        if (!item)
            return false;
        popup.openChild(entry, item);
        if (childLoader.item)
            childLoader.item.moveHighlight(1);
        return true;
    }

    function entryItemAt(i) {
        for (let n = 0; n < entryColumn.children.length; n++) {
            const child = entryColumn.children[n];
            if (child.index === i)
                return child;
        }
        return null;
    }

    // At most one submenu is open per level, which is what keeps the chain a
    // chain rather than a spray of popups.
    property var childEntry: null

    function openChild(entry, item) {
        if (popup.childEntry === entry)
            return;
        popup.closeChild();
        popup.childEntry = entry;
        popup.menu.send("open " + entry.id);
        childLoader.setSource("GlobalMenuPopup.qml", {
            menu: popup.menu,
            anchorItem: item,
            bar: popup.bar,
            parentEntry: entry,
            submenu: true
        });
    }

    function closeChild() {
        if (!popup.childEntry)
            return;
        popup.menu.send("close " + popup.childEntry.id);
        popup.childEntry = null;
        childLoader.setSource("");
        // The closed level's window took the keyboard; take it back here so a
        // second Escape or Left is not swallowed by a dead window.
        keyReceiver.forceActiveFocus();
    }

    // Each level is its own window, so the chain's focus grab has to list all of
    // them; a window the grab does not know about counts as "outside".
    Component.onCompleted: popup.menu.registerPopup(popup)
    Component.onDestruction: popup.menu.unregisterPopup(popup)

    // Keys only arrive at a window that has an item holding active focus, and
    // the compositor hands the keyboard to whichever window of the chain it
    // last focused, so every level listens and forwards to the same handler.
    Item {
        id: keyReceiver
        anchors.fill: parent
        focus: true
        Component.onCompleted: keyReceiver.forceActiveFocus()

        Keys.onPressed: event => {
            if (popup.menu.handleKey(event.key))
                event.accepted = true;
        }
    }

    Loader {
        id: childLoader
        onLoaded: item.dismissed.connect(popup.dismissed)
    }

    Rectangle {
        id: background
        readonly property real innerPadding: 4

        x: 0
        y: popup.attachedToBar && !popup.growsUp ? -1 : 0
        width: implicitWidth
        height: implicitHeight
        // The bar's own material, not a surface of its own. Layer 0 tracks the
        // wallpaper theme, so a menu in it sat at a different brightness than the
        // bar it hangs off, and moved every time the wallpaper did.
        color: popup.surface
        radius: Appearance.rounding.small
        // Square off whichever edge meets the bar, so the two read as one
        // surface rather than a card that happens to be parked there.
        topLeftRadius: popup.attachedToBar && !popup.growsUp ? 0 : radius
        topRightRadius: popup.attachedToBar && !popup.growsUp ? 0 : radius
        bottomLeftRadius: popup.growsUp ? 0 : radius
        bottomRightRadius: popup.growsUp ? 0 : radius
        border.width: 1
        border.color: popup.scheme.lightText
            ? Qt.rgba(1, 1, 1, 0.16)
            : Qt.rgba(0, 0, 0, 0.16)
        clip: true

        implicitWidth: Math.max(152, Math.min(420, entryColumn.implicitWidth + innerPadding * 2))
        implicitHeight: entryColumn.implicitHeight + innerPadding * 2

        // The glass is there at once and only the entries fade: Hyprland blurs no pixel
        // under 0.2 alpha (quickshell:barMenu), so faded glass would come in clear and
        // turn frosted part way.
        scale: 0.975
        transformOrigin: popup.growsUp ? Item.BottomLeft : popup.turned ? Item.TopRight : Item.TopLeft
        Component.onCompleted: {
            entryColumn.opacity = 1;
            scale = 1;
        }
        Behavior on scale {
            enabled: !Appearance.reduceMotion
            NumberAnimation {
                duration: Appearance.animationDuration.snap
                easing.type: Easing.OutCubic
            }
        }

        Rectangle { // top bevel, a free edge only
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                leftMargin: 10
                rightMargin: 10
            }
            visible: !popup.attachedToBar || popup.growsUp
            height: 1
            color: popup.scheme.lightText
                ? Qt.rgba(1, 1, 1, 0.08)
                : Qt.rgba(1, 1, 1, 0.72)
        }

        ColumnLayout {
            id: entryColumn
            anchors {
                fill: parent
                margins: background.innerPadding
            }
            spacing: 0
            opacity: 0
            Behavior on opacity {
                NumberAnimation {
                    duration: Appearance.animationDuration.snap
                    easing.type: Easing.OutCubic
                }
            }

            Repeater {
                model: popup.entries

                delegate: GlobalMenuEntry {
                    id: entryItem
                    required property var modelData
                    required property int index

                    entry: modelData
                    menu: popup.menu
                    scheme: popup.scheme
                    Layout.fillWidth: true
                    keyHighlighted: popup.highlight === index

                    onEntered: {
                        popup.highlight = index;
                        if (hasChildren)
                            popup.openChild(modelData, entryItem);
                        else
                            popup.closeChild();
                    }
                    onTriggered: popup.activate(modelData)
                    onOpenChildren: popup.openChild(modelData, entryItem)
                }
            }
        }
    }
}
