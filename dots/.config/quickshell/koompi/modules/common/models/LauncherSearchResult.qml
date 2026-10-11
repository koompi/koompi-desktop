import QtQuick
import Quickshell

QtObject {
    enum IconType { Material, Text, System, None }
    enum FontType { Normal, Monospace }

    // General stuff
    property string type: ""
    // drawn above this row; set on the first row of a group
    property string heading: ""
    property var fontType: LauncherSearchResult.FontType.Normal
    property string name: ""
    property string rawValue: ""
    property string iconName: ""
    property var iconType: LauncherSearchResult.IconType.None
    property string verb: ""
    property bool blurImage: false
    // identifies the row across result sets, so a late row cannot move the cursor
    property string key: `${type}|${id}|${rawValue}|${name}`
    // set on a file row: Space previews this path (koompi-quicklook)
    property string previewPath: ""
    // beats the name match when ranking the Top Hit; 0 leaves it to the match
    property int tier: 0
    // the sigil a "Show all" row switches to
    property string scopePrefix: ""
    // run it without closing Search (a "Show all" row changes the query)
    property bool keepOpen: false
    property var execute: () => {
        print("Not implemented");
    }
    property var actions: []
    
    // Stuff needed for DesktopEntry 
    property string id: ""
    property bool shown: true
    property string comment: ""
    property bool runInTerminal: false
    property string genericName: ""
    property list<string> keywords: []

    // Extra stuff to allow for more flexibility
    property string category: type
}
