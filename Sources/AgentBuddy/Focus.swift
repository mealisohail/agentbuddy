import AppKit
import Darwin

/// Brings the window that hosts a session to the front.
enum Focus {
    static let editors: Set<String> = [
        "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.vscodium",
        "com.todesktop.230313mzl4w4u92", "com.exafunction.windsurf",
    ]

    @MainActor static func open(_ s: Session) {
        let app = hostApp(pid: s.pid)
        if let app, let bid = app.bundleIdentifier, editors.contains(bid), let url = app.bundleURL {
            // Opening the workspace folder with the editor focuses the window that already has it open.
            let folder = ideLock(for: s.cwd)?.folder ?? s.cwd
            NSWorkspace.shared.open([URL(fileURLWithPath: folder)], withApplicationAt: url, configuration: NSWorkspace.OpenConfiguration())
            return
        }
        if let tty = tty(of: s.pid), let bid = app?.bundleIdentifier, selectTab(tty: tty, bundleId: bid) { return }
        app?.activate()
    }

    /// Types a prompt into the session's terminal. Editors have no input API, so there we copy it and open the window.
    @MainActor static func send(_ raw: String, to s: Session) -> (typed: Bool, message: String) {
        // one line: a newline would submit early in Claude Code's prompt
        let text = raw.components(separatedBy: .newlines).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return (false, "Nothing to send") }
        if let pane = s.tmux?.split(separator: ".").last.map(String.init), let tmux = tmuxPath {
            let ok = run(tmux, ["send-keys", "-t", pane, "-l", text]) && run(tmux, ["send-keys", "-t", pane, "Enter"])
            if ok { return (true, "Sent") }
        }
        if !s.isEditor, let tty = tty(of: s.pid), let bid = hostApp(pid: s.pid)?.bundleIdentifier, type(text, tty: tty, bundleId: bid) {
            return (true, "Sent")
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        open(s)
        return (false, "Copied — paste with ⌘V in \(s.host)")
    }

    static let tmuxPath = ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"].first { FileManager.default.isExecutableFile(atPath: $0) }

    static func run(_ exe: String, _ args: [String]) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }

    private static func type(_ text: String, tty: String, bundleId: String) -> Bool {
        let quoted = text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let script: String
        switch bundleId {
        case "com.apple.Terminal":
            script = """
            tell application "Terminal"
              repeat with w in windows
                repeat with t in tabs of w
                  if tty of t is "\(tty)" then
                    do script "\(quoted)" in t
                    return true
                  end if
                end repeat
              end repeat
            end tell
            return false
            """
        case "com.googlecode.iterm2":
            script = """
            tell application "iTerm2"
              repeat with w in windows
                repeat with t in tabs of w
                  repeat with s in sessions of t
                    if tty of s is "\(tty)" then
                      tell s to write text "\(quoted)"
                      return true
                    end if
                  end repeat
                end repeat
              end repeat
            end tell
            return false
            """
        default: return false
        }
        var err: NSDictionary?
        return NSAppleScript(source: script)?.executeAndReturnError(&err).booleanValue ?? false
    }

    /// Walks up the process tree to the first regular GUI app (Terminal, iTerm, VS Code…).
    static func hostApp(pid: pid_t) -> NSRunningApplication? {
        var p = pid
        for _ in 0..<40 where p > 1 {
            if let app = NSRunningApplication(processIdentifier: p), app.activationPolicy == .regular { return app }
            p = parent(of: p)
        }
        return nil
    }

    static func parent(of pid: pid_t) -> pid_t {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return 0 }
        return info.kp_eproc.e_ppid
    }

    static func tty(of pid: pid_t) -> String? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, info.kp_eproc.e_tdev != -1,
              let name = devname(info.kp_eproc.e_tdev, S_IFCHR) else { return nil }
        return "/dev/" + String(cString: name)
    }

    /// Terminal and iTerm expose their tabs' ttys over AppleScript; selecting the matching tab beats activating a random window.
    /// First use triggers macOS's Automation consent prompt; if refused we fall back to plain activation.
    private static func selectTab(tty: String, bundleId: String) -> Bool {
        let script: String
        switch bundleId {
        case "com.apple.Terminal":
            script = """
            tell application "Terminal"
              repeat with w in windows
                repeat with t in tabs of w
                  if tty of t is "\(tty)" then
                    set selected of t to true
                    set index of w to 1
                    activate
                    return true
                  end if
                end repeat
              end repeat
            end tell
            return false
            """
        case "com.googlecode.iterm2":
            script = """
            tell application "iTerm2"
              repeat with w in windows
                repeat with t in tabs of w
                  repeat with s in sessions of t
                    if tty of s is "\(tty)" then
                      select w
                      select t
                      select s
                      activate
                      return true
                    end if
                  end repeat
                end repeat
              end repeat
            end tell
            return false
            """
        default: return false
        }
        var err: NSDictionary?
        return NSAppleScript(source: script)?.executeAndReturnError(&err).booleanValue ?? false
    }

    /// ~/.claude/ide/*.lock lists each editor window's workspace folders; pick the deepest one containing cwd.
    static func ideLock(for cwd: String) -> (name: String, folder: String)? {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/ide")
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        var best: (name: String, folder: String)?
        for f in files where f.pathExtension == "lock" {
            guard let data = try? Data(contentsOf: f),
                  let d = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let pid = d["pid"] as? Int, kill(pid_t(pid), 0) == 0 || errno == EPERM else { continue }
            for folder in d["workspaceFolders"] as? [String] ?? [] where cwd == folder || cwd.hasPrefix(folder + "/") {
                if folder.count > (best?.folder.count ?? -1) {
                    best = (d["ideName"] as? String ?? "VS Code", folder)
                }
            }
        }
        if let b = best, b.name == "Visual Studio Code" { return ("VS Code", b.folder) }
        return best
    }
}
