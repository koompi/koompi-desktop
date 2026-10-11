pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "notification-system.js" as System

/**
 * Show a file in the file manager with it selected (FileManager1.ShowItems).
 * A folder's default app is not always a file manager (here it can be an editor),
 * so xdg-open on the folder is only the fallback when no FileManager1 answers.
 */
Singleton {
    id: root

    // the file a notice's body names, or "" (notification-system.js)
    function pathIn(body: string): string {
        return System.filePath(body);
    }

    function show(path: string): void {
        if (!path)
            return;
        call.path = path;
        call.command = ["gdbus", "call", "--session", "--dest", "org.freedesktop.FileManager1",
            "--object-path", "/org/freedesktop/FileManager1", "--method", "org.freedesktop.FileManager1.ShowItems",
            "['" + encodeURI("file://" + path).replace(/'/g, "%27") + "']", ""];
        call.running = true;
    }

    Process {
        id: call
        property string path: ""
        onExited: exitCode => {
            if (exitCode !== 0)
                Quickshell.execDetached(["xdg-open", call.path.replace(/\/[^\/]*$/, "") || "/"]);
        }
    }
}
