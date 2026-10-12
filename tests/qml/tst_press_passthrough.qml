import QtQuick
import QtTest

// The engaged overlay in SidebarLeft/SidebarRight sits at z: 100 over the panel's
// content. Whatever handler it holds must see the press and still let the button
// underneath get its click.
Item {
    id: top
    width: 300
    height: 300

    Item {
        id: panel
        anchors.fill: parent
        property bool engaged: false
        property int clicks: 0
        Item {
            anchors.fill: parent
            z: 100
            PointHandler {
                onActiveChanged: if (active) panel.engaged = true
            }
        }
        MouseArea {
            anchors.fill: parent
            onClicked: panel.clicks++
        }
    }

    TestCase {
        name: "pressPassthrough"
        when: windowShown
        function test_click_reaches_the_button() {
            mouseClick(top, 50, 50);
            compare(panel.engaged, true, "the overlay saw the press");
            compare(panel.clicks, 1, "the button under the overlay got the click");
        }
    }
}
