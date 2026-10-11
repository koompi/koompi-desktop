import QtQuick
import Quickshell.Io

Process {
    id: root

    required property string tool
    required property var args
    required property string row
    signal finished(int code, string out, string err)

    property bool exited: false
    property bool outEnded: false
    property bool errEnded: false
    property int code: -1

    // exit status and both streams arrive separately, in any order
    function settle() {
        if (!root.exited || !root.outEnded || !root.errEnded)
            return;
        root.finished(root.code, outText.text.trim(), errText.text.trim());
        root.destroy();
    }

    command: [root.tool, ...root.args]
    running: true
    stdout: StdioCollector {
        id: outText
        onStreamFinished: {
            root.outEnded = true;
            root.settle();
        }
    }
    stderr: StdioCollector {
        id: errText
        onStreamFinished: {
            root.errEnded = true;
            root.settle();
        }
    }
    onExited: (exitCode, exitStatus) => {
        root.code = exitStatus === 0 ? exitCode : -1;
        root.exited = true;
        root.settle();
    }
    onRunningChanged: {
        if (root.running || root.exited)
            return;
        root.exited = root.outEnded = root.errEnded = true;
        root.settle();
    }
}
