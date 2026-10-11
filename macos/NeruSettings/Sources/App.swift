import AppKit

// The windows' way into the daemon they run in: the C functions in
// internal/adapter/settingsui/settingsui.h. The only file that touches Go, so
// bin/check-settings and bin/render-settings build without it.

/// Shows "settings", "tutorial" or "training". Go calls it from any thread.
@_cdecl("HomekeySettingsOpen")
public func homekeySettingsOpen(_ window: UnsafeMutablePointer<CChar>) {
    let name = String(cString: window) // copied: Go frees it when this returns
    DispatchQueue.main.async {
        MainActor.assumeIsolated {
            if Neru.link == nil { Neru.link = InProcessDaemon() }
            Windows.show(name)
        }
    }
}

final class InProcessDaemon: DaemonLink {
    /// HomekeyWatch and HomekeyWatchStop run here, in order.
    private let watchQueue = DispatchQueue(label: "neru.settings.watch")

    func send(_ action: String, _ args: [String]) -> (ok: Bool, out: String) {
        // The daemon may wait on the main thread (overlays, the event tap)
        // while holding what this request needs: a deadlock from main.
        dispatchPrecondition(condition: .notOnQueue(.main))
        guard let request = try? JSONSerialization.data(withJSONObject: ["action": action, "args": args]),
              let reply = String(decoding: request, as: UTF8.self).withCString({ HomekeyCommand(UnsafeMutablePointer(mutating: $0)) })
        else { return (false, "Could not ask \(Neru.appName)") }
        defer { free(reply) }
        let json = Neru.json(String(cString: reply)) ?? [:]
        guard json["success"] as? Bool == true else { return (false, json["message"] as? String ?? "No answer") }
        switch json["data"] {
        case nil: return (true, "")
        case let text as String: return (true, text)
        case let data?:
            let out = try? JSONSerialization.data(withJSONObject: data, options: .fragmentsAllowed)
            return (true, out.map { String(decoding: $0, as: UTF8.self) } ?? "")
        }
    }

    func watch(_ line: @escaping (String?) -> Void) -> () -> Void {
        let owner = Unmanaged.passRetained(LineBox(line)).toOpaque() // released after the nil line
        var handle: UInt = 0
        watchQueue.async {
            handle = HomekeyWatch({ owner, cLine in
                let box = Unmanaged<LineBox>.fromOpaque(owner!)
                let text = cLine.map { String(cString: $0) } // copied: Go frees it
                DispatchQueue.main.async {
                    box.takeUnretainedValue().line(text)
                    if text == nil { box.release() }
                }
            }, owner)
        }
        return { self.watchQueue.async { HomekeyWatchStop(handle) } }
    }

    private final class LineBox {
        let line: (String?) -> Void
        init(_ line: @escaping (String?) -> Void) { self.line = line }
    }
}
