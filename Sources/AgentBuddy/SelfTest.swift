import Foundation

/// `AgentBuddy --selftest` — asserts on the parsing and hook-payload logic.
enum SelfTest {
    static func run() -> Never {
        assert(Transcript.projectDirName("/Users/a.b/my_proj") == "-Users-a-b-my-proj")

        let lines = [
            #"{"type":"ai-title","aiTitle":"Old title"}"#,
            #"{"type":"user","message":{"content":"first prompt"}}"#,
            #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"a","name":"Read","input":{"file_path":"/x/old.md"}}]}}"#,
            #"{"type":"user","message":{"content":"render the video"}}"#,
            #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t","name":"TodoWrite","input":{"todos":[{"content":"A","status":"completed","activeForm":"Doing A"},{"content":"B","status":"in_progress","activeForm":"Doing B"},{"content":"C","status":"pending","activeForm":"Doing C"}]}}]}}"#,
            #"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t","content":"ok"}]}}"#,
            #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"b","name":"Bash","input":{"command":"npm test","description":"Run tests"}}]}}"#,
            #"{"type":"assistant","isSidechain":true,"message":{"content":[{"type":"tool_use","id":"s","name":"Read","input":{}}]}}"#,
            #"{"type":"user","message":{"content":"<command-name>/clear</command-name>"}}"#,
            #"{"type":"custom-title","customTitle":"My session"}"#,
            "not json",
        ].joined(separator: "\n")
        var info = Transcript.parse(lines)
        assert(info.title == "My session", "custom title wins over ai title")
        assert(info.prompt == "render the video", "wrapper/meta messages are not prompts")
        assert(info.steps.map(\.text) == ["Update plan", "Run tests"], "steps reset per turn, sidechains ignored")
        assert(info.steps[0].state == .done && info.steps[1].state == .running)
        assert(info.todos.map(\.state) == [.done, .running, .pending] && info.todos[1].text == "Doing B")
        assert(info.lastCommand == "npm test" && info.commandRunning)

        info = Transcript.parse(lines + "\n" + #"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"b","is_error":true,"content":[{"type":"text","text":"1 failed"}]}]}}"#)
        assert(info.steps[1].state == .failed && info.lastOutput == "1 failed" && !info.commandRunning)

        // incremental: a half-written line waits; appended lines continue the same turn
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("agentbuddy-selftest.jsonl")
        try! (#"{"type":"user","message":{"content":"go"}}"# + "\n" + #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"x","name":"Read","input":{"file_path":"/a/b.md"}}]}"#).write(to: tmp, atomically: true, encoding: .utf8)
        var p = Parser()
        assert(p.update(from: tmp) && p.info.prompt == "go" && p.info.steps.isEmpty)
        let fh = try! FileHandle(forWritingTo: tmp); fh.seekToEndOfFile()
        fh.write(Data(("}\n" + #"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"x","content":"ok"}]}}"# + "\n").utf8)); try! fh.close()
        assert(p.update(from: tmp) && p.info.steps.map(\.state) == [.done] && p.info.steps[0].text == "Read b.md")
        try! "{}\n".write(to: tmp, atomically: true, encoding: .utf8)
        assert(!p.update(from: tmp), "shrunk file signals a restart")

        let q: [String: Any] = ["questions": [["question": "Which hook?", "options": [["label": "Pain"]]]]]
        let out = QuestionCard.answered(q, answers: ["Pain"])
        assert((out["answers"] as? [String: String]) == ["Which hook?": "Pain"] && out["questions"] != nil)

        let deny = String(decoding: HookBridge.response(.deny)!, as: UTF8.self)
        assert(deny.contains(#""behavior":"deny""#) && deny.contains("PermissionRequest"))
        assert(HookBridge.response(.passthrough) == nil)

        settingsTests()
        MainActor.assumeIsolated { resolveTests() }
        print("selftest ok")
        exit(0)
    }
}

import SwiftUI

extension SelfTest {
    /// settings.json edits must keep everything else, replace old/moved hooks, and never clobber a broken file.
    static func settingsTests() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("agentbuddy-selftest-\(getpid())")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let real = HookInstaller.settings
        defer { HookInstaller.settings = real }
        HookInstaller.settings = dir.appendingPathComponent("settings.json")

        let original = #"{"permissions":{"allow":["Bash(ls)"]},"hooks":{"Stop":[{"hooks":[{"type":"command","command":"say done"}]}],"PermissionRequest":[{"matcher":"Bash","hooks":[{"type":"command","command":"other-tool"}]},{"matcher":"*","hooks":[{"type":"command","command":"'/old/AgentHuddle.app/Contents/MacOS/AgentHuddle' --hook"}]}]}}"#
        try! original.write(to: HookInstaller.settings, atomically: true, encoding: .utf8)
        assert(HookInstaller.isInstalled && !HookInstaller.pointsHere, "legacy hook seen as ours but stale")
        try! HookInstaller.set(installed: true)
        var root = try! HookInstaller.load()
        var pr = (root["hooks"] as! [String: Any])["PermissionRequest"] as! [[String: Any]]
        assert(pr.count == 2, "other tool kept, legacy replaced by one entry")
        assert(HookInstaller.pointsHere && (root["permissions"] as? [String: Any]) != nil && (root["hooks"] as! [String: Any])["Stop"] != nil)
        try! HookInstaller.set(installed: true)                       // idempotent
        pr = ((try! HookInstaller.load())["hooks"] as! [String: Any])["PermissionRequest"] as! [[String: Any]]
        assert(pr.count == 2)
        try! HookInstaller.set(installed: false)
        root = try! HookInstaller.load()
        pr = (root["hooks"] as! [String: Any])["PermissionRequest"] as! [[String: Any]]
        assert(pr.count == 1 && !HookInstaller.isInstalled, "only ours removed")
        assert(FileManager.default.fileExists(atPath: HookInstaller.settings.appendingPathExtension("agentbuddy-backup").path))

        let broken = "{ not json"
        try! broken.write(to: HookInstaller.settings, atomically: true, encoding: .utf8)
        assert((try? HookInstaller.set(installed: true)) == nil, "refuses to edit unparseable settings")
        assert((try? String(contentsOf: HookInstaller.settings, encoding: .utf8)) == broken, "broken file untouched")

        try! FileManager.default.removeItem(at: HookInstaller.settings)
        try! HookInstaller.set(installed: true)                       // no settings.json yet
        assert(HookInstaller.pointsHere)
    }

    /// A card must go away when the question/permission was answered in VS Code or the terminal instead.
    @MainActor static func resolveTests() {
        let m = AppModel.shared
        func session(_ status: Session.Status, steps: [Step] = []) -> Session {
            var s = Session(id: "s1", pid: 1, cwd: "/x", entrypoint: "cli", name: nil, startedAt: 0, status: status,
                            waitingFor: nil, statusSince: Date())
            s.info.steps = steps
            return s
        }
        var replies: [String] = []
        func park() {
            m.pending["s1"] = PendingRequest(sessionId: "s1", tool: "Bash", input: [:]) { d in replies.append("\(d)") }
        }
        let running = [Step(id: "t1", tool: "Bash", text: "x", state: .running)]
        let done = [Step(id: "t1", tool: "Bash", text: "x", state: .done)]

        park(); m.resolveElsewhere([session(.busy, steps: running)])
        assert(m.pending["s1"] != nil, "held while Claude waits on the hook")
        m.resolveElsewhere([session(.waiting, steps: running)])
        assert(m.pending["s1"] != nil, "native prompt shown in parallel: still answerable here")
        m.resolveElsewhere([session(.busy, steps: running)])
        assert(m.pending["s1"] == nil && replies.count == 1, "native prompt answered → card cleared")

        park(); m.resolveElsewhere([session(.busy, steps: running)]); m.resolveElsewhere([session(.busy, steps: done)])
        assert(m.pending["s1"] == nil, "tool call finished in the transcript → card cleared")

        park(); m.resolveElsewhere([session(.idle)])
        assert(m.pending["s1"] == nil, "turn ended → card cleared")

        park(); m.resolveElsewhere([])
        assert(m.pending["s1"] == nil && !m.holdingOpen, "session gone → card cleared")
    }
}

/// `AgentBuddy --snapshot out.png [light]` — renders the panel with live sessions, for checking layout without screen-recording rights.
enum Snapshot {
    nonisolated(unsafe) static var active = false

    @MainActor static func run() -> Never {
        active = true
        let args = CommandLine.arguments
        let out = args.firstIndex(of: "--snapshot").map { args.indices.contains($0 + 1) ? args[$0 + 1] : "snapshot.png" } ?? "snapshot.png"
        let h = AppModel.shared
        if args.contains("--demo") { demo(h) } else {
            h.refresh()
            while h.reading { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        }
        if args.contains("--detail") { h.selected = h.visible.first?.id }
        if args.contains("--fake") {
            // demo the attention cards on the first two sessions
            let ids = h.visible.map(\.id)
            if ids.count > 0 { h.pending[ids[0]] = PendingRequest(sessionId: ids[0], tool: "Bash", input: ["command": "npx hyperframes render . -o out.mp4"]) { _ in } }
            if ids.count > 1 {
                h.pending[ids[1]] = PendingRequest(sessionId: ids[1], tool: "AskUserQuestion", input: ["questions": [[
                    "header": "Hook", "question": "Which hook should I use?", "multiSelect": false,
                    "options": [["label": "The pain one"], ["label": "The number one"], ["label": "The question one"]]]]]) { _ in }
            }
        }
        h.pinned = !args.contains("--collapsed")
        func view(_ height: CGFloat) -> some View {
            IslandView(notch: NotchMetrics(width: 190, height: 34, hasNotch: true), maxHeight: 2400)
                .frame(width: 560, height: height, alignment: .top)
                .background(LinearGradient(colors: [Color(white: 0.75), Color(white: 0.55)], startPoint: .top, endPoint: .bottom))
        }
        var r = ImageRenderer(content: view(1500))
        _ = r.nsImage                                                     // first passes measure the content
        for _ in 0..<5 { RunLoop.main.run(until: Date().addingTimeInterval(0.05)); _ = r.nsImage }
        r = ImageRenderer(content: view(h.islandSize.height + 40))       // crop to the island
        r.scale = 2
        for _ in 0..<3 { RunLoop.main.run(until: Date().addingTimeInterval(0.05)); _ = r.nsImage }
        guard let img = r.nsImage, let tiff = img.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { print("render failed"); exit(1) }
        try? png.write(to: URL(fileURLWithPath: out))
        print("wrote \(out)")
        exit(0)
    }
}

extension Snapshot {
    /// Made-up sessions for README screenshots, so nobody's real project names end up in docs.
    @MainActor static func demo(_ h: AppModel) {
        func step(_ i: Int, _ tool: String, _ text: String, _ st: Step.State = .done) -> Step { Step(id: "\(text)\(i)", tool: tool, text: text, state: st) }
        func make(_ id: String, _ title: String, _ folder: String, _ status: Session.Status, _ started: Double, host: String,
                  prompt: String, steps: [Step] = [], todos: [Step] = [], ago: Double = 0, cmd: String? = nil, out: String? = nil) -> Session {
            var s = Session(id: id, pid: 1, cwd: "/Users/you/code/\(folder)", entrypoint: host == "VS Code" ? "claude-vscode" : "cli",
                            name: nil, startedAt: started, status: status, waitingFor: nil, statusSince: Date().addingTimeInterval(-ago))
            s.host = host
            s.info.title = title; s.info.prompt = prompt; s.info.steps = steps; s.info.todos = todos
            s.info.turnStart = Date().addingTimeInterval(-ago - 134); s.info.lastActivity = Date().addingTimeInterval(-ago)
            s.info.lastCommand = cmd; s.info.lastOutput = out; s.info.commandRunning = status == .busy && cmd != nil
            return s
        }
        let busySteps = [step(1, "Read", "Read checkout.ts"), step(2, "Grep", "Search applyCoupon"), step(3, "Edit", "Edit checkout.ts"),
                         step(4, "Bash", "Run unit tests", .failed), step(5, "Edit", "Edit coupon.ts"), step(6, "Bash", "Run unit tests", .running)]
        let todos = [step(1, "Todo", "Map the API routes"), step(2, "Todo", "Write endpoint docs"), step(3, "Todo", "Adding request examples", .running),
                     step(4, "Todo", "Review with OpenAPI spec", .pending)]
        h.sessions = [
            make("a", "Fix coupon rounding bug", "shop-api", .busy, 1, host: "Terminal", prompt: "coupons round down wrong for JPY, fix it",
                 steps: busySteps, cmd: "npm test -- coupon", out: nil),
            make("b", "Release v2.4 notes", "web-app", .busy, 2, host: "VS Code", prompt: "draft release notes from merged PRs",
                 steps: [step(1, "Bash", "List merged PRs"), step(2, "Bash", "Run release script", .running)]),
            make("c", "Write API docs", "shop-api", .busy, 3, host: "iTerm2", prompt: "document every public endpoint", todos: todos),
            make("d", "Pick a chart library", "dashboard", .busy, 4, host: "VS Code", prompt: "compare chart libraries for the dashboard"),
            make("e", "Upgrade to React 19", "web-app", .idle, 5, host: "VS Code", prompt: "upgrade react and fix breakages",
                 steps: [step(1, "Bash", "npm install"), step(2, "Edit", "Edit App.tsx")], ago: 600),
        ]
        h.pending["b"] = PendingRequest(sessionId: "b", tool: "Bash", input: ["command": "./scripts/release.sh --tag v2.4.0"]) { _ in }
        h.pending["d"] = PendingRequest(sessionId: "d", tool: "AskUserQuestion", input: ["questions": [[
            "header": "Library", "question": "Which chart library should I use?", "multiSelect": false,
            "options": [["label": "Recharts", "description": "Simple, React-first"], ["label": "ECharts", "description": "Huge feature set"],
                        ["label": "Visx", "description": "Low-level, flexible"]]]]]) { _ in }
        if CommandLine.arguments.contains("--calm") { h.pending = [:] }
    }
}
