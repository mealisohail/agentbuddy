import Foundation
import Darwin

/// Claude Code runs `AgentBuddy --hook` for every PermissionRequest. The hook forwards the request to the
/// running app over a unix socket and blocks until the user answers in the panel.
/// App not running / socket gone → the hook prints nothing and Claude Code shows its normal prompt.
enum HookBridge {
    static let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".agentbuddy")
    static let socketPath = dir.appendingPathComponent("agentbuddy.sock").path

    static func connect() -> Int32? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var addr = address()
        let ok = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        if ok != 0 { close(fd); return nil }
        return fd
    }

    static func address() -> sockaddr_un {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { buf in
            let bytes = Array(socketPath.utf8.prefix(buf.count - 1))
            buf.copyBytes(from: bytes)
            buf[bytes.count] = 0
        }
        return addr
    }

    static func readAll(_ fd: Int32, limit: Int = 16 << 20) -> Data {
        var data = Data()
        var buf = [UInt8](repeating: 0, count: 65536)
        while data.count < limit {
            let n = read(fd, &buf, buf.count)
            if n <= 0 { break }
            data.append(buf, count: n)
        }
        return data
    }

    static func writeAll(_ fd: Int32, _ data: Data) {
        data.withUnsafeBytes { raw in
            var off = 0
            while off < raw.count {
                let n = write(fd, raw.baseAddress! + off, raw.count - off)
                if n <= 0 { return }
                off += n
            }
        }
    }

    // MARK: hook side (separate short-lived process)

    static func runHook() -> Never {
        let input = FileHandle.standardInput.readDataToEndOfFile()
        guard let fd = connect() else { exit(0) }
        // Length-prefixed, and the write side stays open: the app treats EOF on this socket as "hook died".
        writeAll(fd, Data("\(input.count)\n".utf8) + input)
        let reply = readAll(fd)
        close(fd)
        FileHandle.standardOutput.write(reply)
        exit(0)
    }

    // MARK: app side

    /// Returns false when another AgentBuddy instance already owns the socket.
    static func startServer() -> Bool {
        if let fd = connect() { close(fd); return false }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        unlink(socketPath)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        var addr = address()
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard fd >= 0, bound == 0, listen(fd, 32) == 0 else { return true }   // app still works, just without Allow/Deny
        chmod(socketPath, 0o600)
        Thread.detachNewThread {
            while true {
                let client = accept(fd, nil, nil)
                if client < 0 { continue }
                var one: Int32 = 1
                setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
                Thread.detachNewThread { handle(client) }
            }
        }
        return true
    }

    private static func handle(_ fd: Int32) {
        defer { close(fd) }
        guard let req = try? JSONSerialization.jsonObject(with: readFramed(fd)) as? [String: Any] else { return }
        if let cmd = req["control"] as? String {
            let out = DispatchQueue.main.sync { MainActor.assumeIsolated { control(cmd, req) } }
            if let data = try? JSONSerialization.data(withJSONObject: out, options: [.sortedKeys]) { writeAll(fd, data) }
            return
        }
        guard let sessionId = req["session_id"] as? String,
              let tool = req["tool_name"] as? String else { return }
        let input = req["tool_input"] as? [String: Any] ?? [:]

        let lock = NSCondition()
        var decision: HookDecision?
        let pending = PendingRequest(sessionId: sessionId, tool: tool, input: input) { d in
            lock.lock(); if decision == nil { decision = d }; lock.signal(); lock.unlock()
        }
        let held = DispatchQueue.main.sync {
            MainActor.assumeIsolated {
                guard AppModel.shared.holdPermissions else { return false }
                AppModel.shared.add(pending)
                return true
            }
        }
        guard held else { return }

        // Wait for the user. If Claude Code gives up (hook timeout, session interrupted/closed) the socket hangs up.
        lock.lock()
        while decision == nil {
            lock.wait(until: Date().addingTimeInterval(0.25))
            if decision == nil && peerGone(fd) {
                lock.unlock()
                DispatchQueue.main.async { MainActor.assumeIsolated { AppModel.shared.drop(pending.id) } }
                return
            }
        }
        let d = decision!
        lock.unlock()
        if let out = response(d) { writeAll(fd, out) }
    }

    private static func readFramed(_ fd: Int32) -> Data {
        var header = Data()
        var b: UInt8 = 0
        while header.count < 20, read(fd, &b, 1) == 1, b != 0x0A { header.append(b) }
        guard let n = Int(String(decoding: header, as: UTF8.self)), n > 0, n < 16 << 20 else { return Data() }
        var data = Data(count: n)
        var got = 0
        while got < n {
            let r = data.withUnsafeMutableBytes { read(fd, $0.baseAddress! + got, n - got) }
            if r <= 0 { return Data() }
            got += r
        }
        return data
    }

    /// Same actions as the buttons, for scripting and the end-to-end test (tests/e2e.sh). The socket is owner-only (0600).
    @MainActor private static func control(_ cmd: String, _ req: [String: Any]) -> [String: Any] {
        let h = AppModel.shared
        let id = req["session"] as? String ?? ""
        switch cmd {
        case "state":
            h.refresh()
            return ["expanded": h.expanded, "holdingOpen": h.holdingOpen, "peeking": h.peeking, "hovering": h.hovering,
                    "quiet": Array(h.quiet), "sessions": h.sessions.map { s -> [String: Any] in
                var d: [String: Any] = ["id": s.id, "status": "\(s.status)", "host": s.host, "title": s.title, "cwd": s.cwd,
                                        "prompt": s.info.prompt ?? "", "steps": s.info.steps.map(\.text),
                                        "visible": h.visible.contains { $0.id == s.id }]
                if let r = h.pending[s.id] { d["pending"] = r.tool }
                return d
            }]
        case "decide":
            guard let r = h.pending[id] else { return ["ok": false, "error": "nothing pending"] }
            switch req["decision"] as? String {
            case "allow": h.decide(id, .allow(nil))
            case "deny": h.decide(id, .deny)
            case "answer": h.decide(id, .allow(QuestionCard.answered(r.input, answers: req["answers"] as? [String] ?? [])))
            default: h.decide(id, .passthrough)
            }
            return ["ok": true]
        case "send":
            guard let s = h.sessions.first(where: { $0.id == id }) else { return ["ok": false, "error": "no such session"] }
            let result = Focus.send(req["text"] as? String ?? "", to: s)
            return ["ok": result.typed, "message": result.message]
        default:
            return ["ok": false, "error": "unknown control"]
        }
    }

    private static func peerGone(_ fd: Int32) -> Bool {
        var p = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        guard poll(&p, 1, 0) > 0 else { return false }
        var b: UInt8 = 0
        return recv(fd, &b, 1, MSG_PEEK) <= 0
    }

    static func response(_ d: HookDecision) -> Data? {
        let decision: [String: Any]
        switch d {
        case .passthrough: return nil
        case .deny: decision = ["behavior": "deny", "message": "The user denied this from AgentBuddy."]
        case .allow(let updated):
            decision = updated.map { ["behavior": "allow", "updatedInput": $0] } ?? ["behavior": "allow"]
        }
        return try? JSONSerialization.data(withJSONObject: ["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": decision]])
    }
}

/// Adds / removes our PermissionRequest hook in ~/.claude/settings.json, preserving everything else.
enum HookInstaller {
    nonisolated(unsafe) static var settings = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")

    static var command: String {
        let exe = Bundle.main.executablePath ?? CommandLine.arguments[0]
        // `|| true`: if the app was deleted without removing the hook, Claude Code just shows its normal prompt
        return "'\(exe.replacingOccurrences(of: "'", with: "'\\''"))' --hook 2>/dev/null || true"
    }

    static func isOurs(_ entry: Any) -> Bool {
        ((entry as? [String: Any])?["hooks"] as? [[String: Any]] ?? []).contains {
            { c in (c.contains("AgentBuddy") || c.contains("AgentHuddle")) && c.contains("--hook") }($0["command"] as? String ?? "")   // AgentHuddle = pre-1.0 name
        }
    }

    /// Installed, and pointing at this copy of the app (it may have been moved, or installed under the old name).
    static var pointsHere: Bool {
        guard let root = try? load() else { return false }
        return ((root["hooks"] as? [String: Any])?["PermissionRequest"] as? [Any] ?? []).contains {
            (($0 as? [String: Any])?["hooks"] as? [[String: Any]] ?? []).contains { $0["command"] as? String == command }
        }
    }

    static var isInstalled: Bool {
        guard let root = try? load() else { return false }
        return ((root["hooks"] as? [String: Any])?["PermissionRequest"] as? [Any] ?? []).contains(where: isOurs)
    }

    static func load() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: settings.path) else { return [:] }
        let data = try Data(contentsOf: settings)
        if data.isEmpty { return [:] }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "AgentBuddy", code: 1, userInfo: [NSLocalizedDescriptionKey: "settings.json is not a JSON object"])
        }
        return root
    }

    /// Throws (and writes nothing) if settings.json can't be parsed, so a hand-edited file is never clobbered.
    static func set(installed: Bool) throws {
        var root = try load()
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        var list = (hooks["PermissionRequest"] as? [Any] ?? []).filter { !isOurs($0) }
        if installed {
            list.append(["matcher": "*", "hooks": [["type": "command", "command": command, "timeout": 600]]])
        }
        hooks["PermissionRequest"] = list.isEmpty ? nil : list
        root["hooks"] = hooks.isEmpty ? nil : hooks

        let backup = settings.appendingPathExtension("agentbuddy-backup")
        if !FileManager.default.fileExists(atPath: backup.path) { try? FileManager.default.copyItem(at: settings, to: backup) }
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: settings, options: .atomic)
    }
}
