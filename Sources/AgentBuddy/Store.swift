import AppKit
import Darwin
import Observation

struct Session: Identifiable, Equatable {
    enum Status: Equatable { case busy, idle, waiting }
    let id: String            // Claude sessionId
    let pid: pid_t
    let cwd: String
    let entrypoint: String
    let name: String?
    let startedAt: Double
    let status: Status
    let waitingFor: String?
    let statusSince: Date
    var host = "Terminal"     // "VS Code", "Cursor", "Terminal", "iTerm", "tmux"…
    var tmux: String?         // "session:@window.%pane" when running inside tmux
    var info = TranscriptInfo()

    var folder: String { (cwd as NSString).lastPathComponent }
    var title: String { info.title ?? name ?? folder }
    var isEditor: Bool { entrypoint.contains("vscode") }
}

/// A PermissionRequest hook call parked until the user decides in the panel.
final class PendingRequest: Identifiable {
    let id = UUID()
    let sessionId: String
    let tool: String
    let input: [String: Any]
    let reply: (HookDecision) -> Void
    var sawNativePrompt = false   // Claude Code showed its own prompt for this too (VS Code does, in parallel with the hook)
    var toolUseIds: Set<String> = []  // transcript tool calls this request could belong to; one finishing = answered somewhere
    init(sessionId: String, tool: String, input: [String: Any], reply: @escaping (HookDecision) -> Void) {
        self.sessionId = sessionId; self.tool = tool; self.input = input; self.reply = reply
    }
    var isQuestion: Bool { tool == "AskUserQuestion" }
    var questions: [[String: Any]] { input["questions"] as? [[String: Any]] ?? [] }
}

enum HookDecision {
    case allow([String: Any]?)   // optional updatedInput
    case deny
    case passthrough             // let Claude Code show its own prompt
}

@MainActor @Observable
final class AppModel {
    static let shared = AppModel()

    var sessions: [Session] = []
    var pending: [String: PendingRequest] = [:]          // sessionId -> request
    var selected: String?                                 // detail view
    var pinned = false
    var hovering = false
    var peeking = false                                   // brief auto-open when something needs you
    var holdingOpen = false                               // a permission arrived; stays open until answered or closed
    var composing = false                                 // typing in a message box
    @ObservationIgnored var suppressHover = false         // after an explicit close, ignore hover until the pointer leaves
    @ObservationIgnored var islandSize: CGSize = .zero    // for click-through hit testing
    var expanded: Bool { pinned || hovering || peeking || holdingOpen || composing }

    /// Explicit close (Esc, close button, click outside): collapse now, even with the pointer still on it.
    func close() {
        pinned = false; peeking = false; holdingOpen = false; composing = false
        if hovering { suppressHover = true }
        hovering = false
        selected = nil
    }
    var muted = UserDefaults.standard.bool(forKey: "muted") { didSet { UserDefaults.standard.set(muted, forKey: "muted") } }
    var holdPermissions = UserDefaults.standard.object(forKey: "hold") as? Bool ?? true {
        didSet { UserDefaults.standard.set(holdPermissions, forKey: "hold") }
    }
    var hookInstalled = HookInstaller.isInstalled
    var hookPromptDismissed = UserDefaults.standard.bool(forKey: "hookPromptDismissed") {
        didSet { UserDefaults.standard.set(hookPromptDismissed, forKey: "hookPromptDismissed") }
    }
    var dismissed: [String: Date] = [:]                   // sessionId -> statusSince when dismissed
    var onAttention: (() -> Void)?
    @ObservationIgnored var isFront: (Session) -> Bool = { Focus.isFront($0) }
    @ObservationIgnored private(set) var quiet: Set<String> = []   // needs you, but you were already looking at it

    @ObservationIgnored private var colors: [String: Int] = [:]
    @ObservationIgnored private let reader = TranscriptReader()
    @ObservationIgnored private var infos: [String: TranscriptInfo] = [:]
    @ObservationIgnored private(set) var reading = false
    @ObservationIgnored private var loaded = false
    @ObservationIgnored private let home = FileManager.default.homeDirectoryForCurrentUser

    var visible: [Session] {
        sessions.filter { s in
            pending[s.id] != nil || dismissed[s.id] != s.statusSince
        }
        .sorted { [pending] a, b in
            // needs you → working → idle; idle ones most recently active first
            func rank(_ s: Session) -> Int { pending[s.id] != nil || s.status == .waiting ? 0 : s.status == .busy ? 1 : 2 }
            if rank(a) != rank(b) { return rank(a) < rank(b) }
            if rank(a) == 2 { return (a.info.lastActivity ?? a.statusSince) > (b.info.lastActivity ?? b.statusSince) }
            return a.startedAt < b.startedAt
        }
    }

    var attentionCount: Int { sessions.filter(needsYou).count }
    var busyCount: Int { sessions.filter { $0.status == .busy }.count }

    func needsYou(_ s: Session) -> Bool { pending[s.id] != nil || s.status == .waiting }

    func colorIndex(_ id: String) -> Int {
        if let c = colors[id] { return c }
        let used = Set(sessions.compactMap { colors[$0.id] })
        let c = (0..<Avatar.palette.count).first { !used.contains($0) } ?? colors.count % Avatar.palette.count
        colors[id] = c
        return c
    }

    // MARK: polling

    func start() {
        refresh()
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated { AppModel.shared.refresh() }
        }
    }

    func refresh() {
        let dir = home.appendingPathComponent(".claude/sessions")
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        var next: [Session] = []
        for f in files where f.pathExtension == "json" {
            guard let data = try? Data(contentsOf: f),
                  let d = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = d["sessionId"] as? String, let pid = d["pid"] as? Int,
                  let cwd = d["cwd"] as? String else { continue }
            let entry = d["entrypoint"] as? String ?? "cli"
            if entry.hasPrefix("sdk") { continue }                        // headless/background SDK workers
            guard Self.isClaudeAlive(pid_t(pid)) else { continue }        // crashed sessions leave their file behind
            let status: Session.Status = switch d["status"] as? String {
                case "busy": .busy
                case "waiting": .waiting
                default: .idle
            }
            let since = (d["statusUpdatedAt"] as? Double ?? d["updatedAt"] as? Double ?? 0) / 1000
            var s = Session(id: id, pid: pid_t(pid), cwd: cwd, entrypoint: entry, name: d["name"] as? String,
                            startedAt: d["startedAt"] as? Double ?? 0, status: status,
                            waitingFor: d["waitingFor"] as? String, statusSince: Date(timeIntervalSince1970: since))
            s.info = infos[id] ?? TranscriptInfo()
            s.tmux = d["tmux"] as? String
            s.host = sessions.first { $0.id == id && $0.pid == s.pid }?.host     // host never changes for a process
                ?? (s.isEditor ? Focus.ideLock(for: cwd)?.name ?? "VS Code"
                    : Focus.hostApp(pid: s.pid)?.localizedName ?? (s.tmux != nil ? "tmux" : "Terminal"))
            next.append(s)
        }
        // same session can appear twice if a resumed session reuses its id — keep the newest process
        var seen: [String: Session] = [:]
        for s in next where (seen[s.id]?.startedAt ?? -1) < s.startedAt { seen[s.id] = s }
        next = Array(seen.values)

        resolveElsewhere(next)
        if loaded { announce(old: sessions, new: next) }
        recheckQuiet(next)
        loaded = true
        if next != sessions { sessions = next }
        let live = Set(next.map(\.id))
        dismissed = dismissed.filter { live.contains($0.key) }
        if let sel = selected, !live.contains(sel) { selected = nil }

        // Transcripts can be tens of MB: read them off the main thread, then fold results in.
        guard !reading else { return }
        reading = true
        let targets = next.map { ($0.id, $0.cwd) }
        DispatchQueue.global(qos: .utility).async { [reader] in
            let fresh = reader.update(targets)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    let h = AppModel.shared
                    h.reading = false
                    h.infos = fresh
                    let updated = h.sessions.map { s in var s = s; s.info = fresh[s.id] ?? s.info; return s }
                    if updated != h.sessions { h.sessions = updated }
                }
            }
        }
    }

    /// The hook isn't told when you answer in VS Code/terminal instead, and Claude Code may leave it running for minutes.
    /// Session state tells us: its own prompt appeared (waiting) and then went away, or the turn ended.
    func resolveElsewhere(_ next: [Session]) {
        for (id, r) in pending {
            let s = next.first { $0.id == id }
            let steps = s?.info.steps ?? []
            if r.toolUseIds.isEmpty {
                r.toolUseIds = Set(steps.filter { $0.tool == r.tool && $0.state == .running }.map(\.id))
            }
            let finished = steps.contains { r.toolUseIds.contains($0.id) && $0.state != .running }
            if s?.status == .waiting && !finished { r.sawNativePrompt = true; continue }
            if s == nil || s?.status == .idle || r.sawNativePrompt || finished {
                pending[id] = nil
                r.reply(.passthrough)       // lets the hook exit; Claude Code already has its answer
            }
        }
        if pending.isEmpty { holdingOpen = false }
    }

    private func announce(old: [Session], new: [Session]) {
        let before = Dictionary(old.map { ($0.id, $0.status) }, uniquingKeysWith: { a, _ in a })
        for s in new {
            if s.status == .waiting, before[s.id] != .waiting, pending[s.id] == nil {
                if isFront(s) { quiet.insert(s.id) } else { attention() }
            }
            if s.status == .idle, before[s.id] == .busy { play("Tink") }
        }
    }

    /// Something that arrived while you were looking at its session: speak up once you look away, if it still needs you.
    /// ponytail: re-checks every refresh tick (one AppleScript call/s) only while something is held back.
    func recheckQuiet(_ next: [Session]) {
        for id in quiet {
            guard let s = next.first(where: { $0.id == id }), pending[id] != nil || s.status == .waiting else { quiet.remove(id); continue }
            guard !isFront(s) else { continue }
            quiet.remove(id)
            if pending[id] != nil { holdingOpen = true }
            attention()
        }
    }

    func attention() {
        play("Glass")
        onAttention?()
    }

    func play(_ name: String) {
        guard !muted else { return }
        NSSound(named: NSSound.Name(name))?.play()
    }

    /// kill(0) says the pid exists; the path check guards against the pid being reused by an unrelated process.
    nonisolated static func isClaudeAlive(_ pid: pid_t) -> Bool {
        guard kill(pid, 0) == 0 || errno == EPERM else { return false }
        var buf = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 else { return true }
        let path = String(cString: buf).lowercased()
        return path.contains("claude") || path.hasSuffix("/node") || path.hasSuffix("/bun")
    }

    // MARK: actions

    func add(_ r: PendingRequest) {
        pending[r.sessionId]?.reply(.passthrough)   // a newer request supersedes an unanswered older one
        pending[r.sessionId] = r
        dismissed[r.sessionId] = nil
        if let s = sessions.first(where: { $0.id == r.sessionId }), isFront(s) { quiet.insert(r.sessionId); return }
        holdingOpen = true
        attention()
    }

    func drop(_ id: UUID) {
        if let key = pending.first(where: { $0.value.id == id })?.key { pending[key] = nil }
        if pending.isEmpty { holdingOpen = false }
    }

    func decide(_ sessionId: String, _ decision: HookDecision) {
        guard let r = pending.removeValue(forKey: sessionId) else { return }
        r.reply(decision)
        if pending.isEmpty { holdingOpen = false }
        if case .passthrough = decision, let s = sessions.first(where: { $0.id == sessionId }) { Focus.open(s) }
    }

    func dismiss(_ s: Session) {
        if pending[s.id] != nil { decide(s.id, .passthrough) }
        dismissed[s.id] = s.statusSince
        if selected == s.id { selected = nil }
    }
}

/// Owns per-session incremental parsers. Only touched from one background block at a time (guarded by `reading`).
final class TranscriptReader: @unchecked Sendable {
    private var parsers: [String: Parser] = [:]
    private var paths: [String: URL] = [:]
    private let projects = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")

    func update(_ sessions: [(id: String, cwd: String)]) -> [String: TranscriptInfo] {
        var out: [String: TranscriptInfo] = [:]
        for (id, cwd) in sessions {
            guard let url = paths[id] ?? locate(id: id, cwd: cwd) else { continue }
            paths[id] = url
            var p = parsers[id] ?? Parser()
            if !p.update(from: url) {               // file was rewritten: start over, keep the known title
                let title = p.info.title
                p = Parser()
                _ = p.update(from: url)
                p.info.title = p.info.title ?? title
            }
            parsers[id] = p
            out[id] = p.info
        }
        let live = Set(sessions.map(\.id))
        parsers = parsers.filter { live.contains($0.key) }
        paths = paths.filter { live.contains($0.key) }
        return out
    }

    private func locate(id: String, cwd: String) -> URL? {
        let direct = projects.appendingPathComponent(Transcript.projectDirName(cwd)).appendingPathComponent("\(id).jsonl")
        if FileManager.default.fileExists(atPath: direct.path) { return direct }
        // session moved folders (cd / worktree): search every project dir
        let dirs = (try? FileManager.default.contentsOfDirectory(at: projects, includingPropertiesForKeys: nil)) ?? []
        return dirs.map { $0.appendingPathComponent("\(id).jsonl") }.first { FileManager.default.fileExists(atPath: $0.path) }
    }
}
