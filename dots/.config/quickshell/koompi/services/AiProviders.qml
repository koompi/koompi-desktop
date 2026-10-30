pragma Singleton
pragma ComponentBehavior: Bound

import qs.services.ai
import "ai/endpoints.js" as Endpoints
import Quickshell
import QtQuick

/**
 * What Settings > AI > Providers needs from the engine package, without the engine.
 * modules/ may not import qs.services.ai (tests/test_ai_engine_split.sh), and
 * Settings should not start the engine through the Ai facade just to write a key.
 * So this holds a KeyGate of its own and forwards to it, which keeps KeyGate the one
 * place that reads and writes keys, with its rule that nothing is written before
 * the keyring has loaded; and it answers endpoints.js's one rule for "local".
 */
Singleton {
    id: root

    // the keyring answered; until then no key can be read or written
    readonly property bool ready: root.gate.keyringReady

    function has(keyId: string): bool {
        return root.gate.hasKey(keyId);
    }
    function store(keyId: string, key: string): bool {
        return root.gate.storeKey(keyId, key);
    }
    function forget(keyId: string): bool {
        return root.gate.forgetKey(keyId);
    }
    function fetch() {
        KeyringStorage.fetchKeyringData();
    }
    // loopback; such an endpoint needs no key unless its entry says so
    function isLocal(endpoint: string): bool {
        return Endpoints.isLocal(endpoint);
    }

    readonly property KeyGate gate: KeyGate {}
}
