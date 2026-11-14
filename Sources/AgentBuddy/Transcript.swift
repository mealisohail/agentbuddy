import Foundation

/// One tool call (or todo) shown in the detail list.
struct Step: Identifiable, Equatable {
    enum State: Equatable { case pending, running, done, failed }
    let id: String
    let tool: String
    let text: String
    var state: State
}

/// What we learn from tailing a session's transcript .jsonl.
struct TranscriptInfo: Equatable {
    var title: String?
    var prompt: String?
    var steps: [Step] = []          // tool calls of the current turn
    var todos: [Step] = []          // latest TodoWrite list, if the session uses one
    var lastCommand: String?
    var lastOutput: String?
    var commandRunning = false
    var lastIsText = false          // last assistant output was prose, not a tool call
    var turnStart: Date?            // when the current prompt was sent
    var lastActivity: Date?         // newest entry in the transcript
}

enum Transcript {
    /// ~/.claude/projects/<cwd with every non-alphanumeric char replaced by "-">/<sessionId>.jsonl
    static func projectDirName(_ cwd: String) -> String {
        String(cwd.map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "-" })
    }

    static func parse(_ text: String) -> TranscriptInfo {
        var p = Parser()
        p.feed(Data(text.utf8))
        return p.info
    }
}

/// Incremental transcript reader: remembers its file offset and parse state, so each poll only reads appended bytes.
struct Parser {
    // ponytail: first read starts 8 MB from the end; a todo list or title older than that shows up once it's rewritten.
    static let initialWindow: UInt64 = 8 << 20
    static let maxLine = 1 << 20          // api-request-blob lines can be MBs; nothing we need is that big

    var info = TranscriptInfo()
    var offset: UInt64 = 0
    private var started = false
    private var aiTitle: String?, customTitle: String?
    private var index: [String: Int] = [:]   // tool_use id -> steps index
    private var bashId: String?

    /// Reads whatever was appended since the last call. Returns false if the file shrank (rewritten) — caller should start over.
    mutating func update(from url: URL) -> Bool {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return true }
        defer { try? fh.close() }
        let size = (try? fh.seekToEnd()) ?? 0
        if size < offset { return false }
        var skipPartial = false
        if !started {
            started = true
            if size > Self.initialWindow { offset = size - Self.initialWindow; skipPartial = true }
        }
        try? fh.seek(toOffset: offset)
        guard var data = try? fh.readToEnd(), !data.isEmpty else { return true }
        guard let lastNL = data.lastIndex(of: 0x0A) else { return true }       // wait for a complete line
        data = data[data.startIndex...lastNL]
        offset += UInt64(data.count)
        if skipPartial, let nl = data.firstIndex(of: 0x0A) { data = data[data.index(after: nl)...] }
        feed(data)
        return true
    }

    mutating func feed(_ data: Data) {
        var info = self.info
        defer { info.title = customTitle ?? aiTitle ?? info.title; self.info = info }
        for line in data.split(separator: 0x0A, omittingEmptySubsequences: true) where line.count < Self.maxLine {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else { continue }
            let stamp = (obj["timestamp"] as? String).flatMap(Self.date)
            if let stamp, ["user", "assistant"].contains(obj["type"] as? String ?? "") { info.lastActivity = stamp }
            switch obj["type"] as? String {
            case "custom-title": customTitle = obj["customTitle"] as? String
            case "ai-title": aiTitle = obj["aiTitle"] as? String
            case "user":
                if obj["isSidechain"] as? Bool == true || obj["isMeta"] as? Bool == true || obj["isCompactSummary"] as? Bool == true { continue }
                let content = (obj["message"] as? [String: Any])?["content"]
                if let s = content as? String {
                    if Self.isRealPrompt(s) { Self.startTurn(&info, &index, prompt: s); info.turnStart = stamp }
                    continue
                }
                for part in content as? [[String: Any]] ?? [] {
                    if part["type"] as? String == "text", let s = part["text"] as? String, Self.isRealPrompt(s) {
                        Self.startTurn(&info, &index, prompt: s)
                        info.turnStart = stamp
                    } else if part["type"] as? String == "tool_result", let id = part["tool_use_id"] as? String {
                        let failed = part["is_error"] as? Bool == true
                        if let i = index[id] { info.steps[i].state = failed ? .failed : .done }
                        if id == bashId {
                            info.lastOutput = Self.resultText(part["content"])
                            info.commandRunning = false
                        }
                    }
                }
            case "assistant":
                if obj["isSidechain"] as? Bool == true { continue }
                for part in (obj["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? [] {
                    switch part["type"] as? String {
                    case "text": info.lastIsText = true
                    case "tool_use":
                        info.lastIsText = false
                        let name = part["name"] as? String ?? "Tool"
                        let input = part["input"] as? [String: Any] ?? [:]
                        let id = part["id"] as? String ?? UUID().uuidString
                        if name == "TodoWrite" { info.todos = Self.todos(input) }
                        if name == "Bash" {
                            bashId = id
                            info.lastCommand = input["command"] as? String
                            info.lastOutput = nil
                            info.commandRunning = true
                        }
                        index[id] = info.steps.count
                        info.steps.append(Step(id: id, tool: name, text: Transcript.describe(name, input), state: .running))
                    default: break
                    }
                }
            default: break
            }
        }
    }

    nonisolated(unsafe) private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static func date(_ s: String) -> Date? { iso.date(from: s) }

    private static func startTurn(_ info: inout TranscriptInfo, _ index: inout [String: Int], prompt: String) {
        info.prompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        info.steps = []
        index = [:]
        info.lastIsText = false
    }

    /// Hook output, slash-command wrappers and interrupts are logged as "user" but aren't prompts.
    private static func isRealPrompt(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return !t.isEmpty && !t.hasPrefix("<") && !t.hasPrefix("[Request interrupted")
    }

    private static func resultText(_ content: Any?) -> String? {
        if let s = content as? String { return s }
        let parts = (content as? [[String: Any]] ?? []).compactMap { $0["text"] as? String }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }

    private static func todos(_ input: [String: Any]) -> [Step] {
        (input["todos"] as? [[String: Any]] ?? []).enumerated().map { i, t in
            let status = t["status"] as? String
            let state: Step.State = status == "completed" ? .done : status == "in_progress" ? .running : .pending
            let text = (state == .running ? t["activeForm"] as? String : nil) ?? t["content"] as? String ?? ""
            return Step(id: "todo\(i)", tool: "Todo", text: text, state: state)
        }
    }
}

extension Transcript {

    static func describe(_ name: String, _ input: [String: Any]) -> String {
        func file(_ k: String = "file_path") -> String { ((input[k] as? String) ?? "").split(separator: "/").last.map(String.init) ?? "" }
        switch name {
        case "Bash":
            if let d = input["description"] as? String, !d.isEmpty { return d }
            return firstLine(input["command"] as? String ?? "command")
        case "Read": return "Read \(file())"
        case "Edit", "MultiEdit": return "Edit \(file())"
        case "Write": return "Write \(file())"
        case "NotebookEdit": return "Edit \(file("notebook_path"))"
        case "Grep", "Glob": return "Search \(input["pattern"] as? String ?? "")"
        case "WebFetch": return "Fetch \(URL(string: input["url"] as? String ?? "")?.host ?? "page")"
        case "WebSearch": return "Search web: \(input["query"] as? String ?? "")"
        case "Agent", "Task": return "Agent: \(input["description"] as? String ?? "subtask")"
        case "Skill": return "Skill: \(input["skill"] as? String ?? "")"
        case "AskUserQuestion": return "Asked you a question"
        case "TodoWrite": return "Update plan"
        case "ExitPlanMode": return "Proposed a plan"
        default:
            if name.hasPrefix("mcp__") {
                let parts = name.split(separator: "_", omittingEmptySubsequences: true)
                return parts.dropFirst().joined(separator: " ")
            }
            return name
        }
    }

    static func firstLine(_ s: String) -> String {
        String(s.split(separator: "\n").first ?? "").trimmingCharacters(in: .whitespaces)
    }
}
