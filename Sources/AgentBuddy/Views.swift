import SwiftUI

// MARK: - Shared controls

struct StatusDot: View {
    let model = AppModel.shared
    @State private var pulse = false
    var body: some View {
        let color: Color = model.attentionCount > 0 ? .orange : model.busyCount > 0 ? .lime : .secondary.opacity(0.5)
        Circle().fill(color).frame(width: 8, height: 8)
            .scaleEffect(pulse && model.attentionCount > 0 ? 1.35 : 1)
            .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: pulse)
            .onAppear { pulse = true }
            .accessibilityLabel(model.attentionCount > 0 ? "\(model.attentionCount) need you" : "\(model.busyCount) working")
    }
}

struct IconButton: View {
    let symbol: String
    let label: String
    let action: () -> Void
    @State private var hover = false
    init(_ symbol: String, label: String, action: @escaping () -> Void) {
        self.symbol = symbol; self.label = label; self.action = action
    }
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 24, height: 24)
                .background(hover ? Color.primary.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(hover ? .primary : .secondary)
        .onHover { hover = $0 }
        .help(label)
        .accessibilityLabel(label)
    }
}

// MARK: - Row

@MainActor func mood(_ s: Session) -> Avatar.Mood {
    AppModel.shared.needsYou(s) ? .alert : s.status == .busy ? .working : .idle
}

struct SessionRow: View {
    let model = AppModel.shared
    let session: Session
    @State private var hover = false

    var body: some View {
        let request = model.pending[session.id]
        let attention = model.needsYou(session)
        let working = session.status == .busy && !attention
        let idle = !working && !attention
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Avatar(color: Avatar.palette[model.colorIndex(session.id)], mood: mood(session))
                    .saturation(idle ? 0.45 : 1)
                    .opacity(idle ? 0.75 : 1)
                    .padding(.top, 2)
                SessionSummary(session: session)
                    .opacity(idle && !hover ? 0.6 : 1)
                VStack(spacing: 6) {
                    IconButton("arrow.up.forward.square", label: "Open in \(session.host)") { Focus.open(session) }
                    IconButton("xmark", label: request != nil ? "Dismiss and answer in \(session.host)" : "Hide until it changes") {
                        withAnimation { model.dismiss(session) }
                    }
                }
            }
            if let request {
                if request.isQuestion { QuestionCard(request: request, host: session.host) }
                else { PermissionCard(request: request, host: session.host) }
            }
        }
        .padding(12)
        .background(working ? Color.lime.opacity(hover ? 0.11 : 0.08) : Color.primary.opacity(hover ? 0.08 : idle ? 0.04 : 0.06),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            // needs you: solid lime ring; working: hairline lime edge; idle: nothing
            if attention || working {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.limeText.opacity(attention ? 1 : 0.35), lineWidth: attention ? 2 : 1)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onHover { hover = $0 }
        .onTapGesture { model.selected = session.id }
        .help("\(session.cwd) · \(session.host)")
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Show details") { model.selected = session.id }
    }
}

/// Title, live activity and progress — shared by the row and the detail header.
struct SessionSummary: View {
    let model = AppModel.shared
    let session: Session
    var large = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(session.title)
                .font(.system(size: large ? 16 : 14, weight: .bold))
                .lineLimit(1)
            activity
                .font(.system(size: 12.5))
                .lineLimit(1)
                .truncationMode(.tail)
            ProgressLine(session: session).padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var activity: some View {
        if let r = model.pending[session.id] {
            Text(r.isQuestion ? "asks a question" : r.tool == "ExitPlanMode" ? "wants to start on a plan" : "needs permission")
                .fontWeight(.semibold).foregroundStyle(Color.limeText)
        } else if session.status == .waiting {
            Text(waitingText).fontWeight(.semibold).foregroundStyle(Color.limeText)
        } else if session.status == .busy {
            HStack(spacing: 5) {
                LiveDot()
                Text(activityText).foregroundStyle(.primary)
            }
        } else {
            Text(activityText).foregroundStyle(.secondary)
        }
    }

    private var waitingText: String {
        switch session.waitingFor {
        case nil, "dialog open": "waiting for you in \(session.host)"
        case let w?: "\(w) in \(session.host)"
        }
    }

    private var activityText: String {
        let info = session.info
        if session.status == .busy {
            if let running = info.steps.last(where: { $0.state == .running }) { return running.text }
            return info.lastIsText ? "Writing a reply…" : "Thinking…"
        }
        if let p = info.prompt { return Transcript.firstLine(p) }
        return "Ready for a prompt"
    }
}

/// Honest progress: a todo list gives a real fraction; otherwise one tick per tool call plus elapsed time.
struct ProgressLine: View {
    let session: Session

    var body: some View {
        let info = session.info
        let todos = info.todos
        let showTodos = !todos.isEmpty && (session.status == .busy || todos.contains { $0.state != .done })
        HStack(spacing: 8) {
            if showTodos {
                let done = todos.filter { $0.state == .done }.count
                caption(Text("\(done)/\(todos.count)").foregroundStyle(Color.limeText).fontWeight(.bold)
                        + Text(" " + (todos.first { $0.state == .running }.map { shortWord($0.text) } ?? "planned")))
                StepStrip(steps: todos, live: session.status == .busy)
            } else if session.status == .busy || session.status == .waiting {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    caption(Text(toolCount(info.steps.count)) + Text(info.turnStart.map { " · " + elapsed(from: $0, to: ctx.date) } ?? ""))
                }
                StepStrip(steps: info.steps, live: session.status == .busy)
            } else {
                let tools = info.steps.isEmpty ? "" : toolCount(info.steps.count) + " · "
                let took = (info.turnStart.flatMap { s in info.lastActivity.map { elapsed(from: s, to: $0) } }).map { "took \($0) · " } ?? ""
                caption(Text(tools + took) + Text(info.lastActivity ?? session.statusSince, format: .relative(presentation: .named)))
                Spacer(minLength: 0)
                Text(session.folder).font(.system(size: 11.5)).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
            }
        }
        .frame(height: 14)
    }

    private func caption(_ t: Text) -> some View {
        t.font(.system(size: 11.5, weight: .medium)).foregroundStyle(.secondary).monospacedDigit().lineLimit(1).fixedSize()
    }
    private func toolCount(_ n: Int) -> String { n == 1 ? "1 tool" : "\(n) tools" }
    private func shortWord(_ s: String) -> String { String(s.split(separator: " ").prefix(2).joined(separator: " ").prefix(18)) }
}

func elapsed(from a: Date, to b: Date) -> String {
    let s = max(0, Int(b.timeIntervalSince(a)))
    return s < 60 ? "\(s)s" : s < 3600 ? "\(s / 60)m \(s % 60)s" : "\(s / 3600)h \(s % 3600 / 60)m"
}

/// One tick per step: done = solid, running = pulsing lime, failed = red, pending = hollow. Newest on the right.
struct StepStrip: View {
    let steps: [Step]
    let live: Bool
    private let maxTicks = 24

    var body: some View {
        let shown = Array(steps.suffix(maxTicks))
        HStack(spacing: 2) {
            ForEach(shown) { step in Tick(state: step.state, live: live) }
            if live && !shown.contains(where: { $0.state == .running }) { Tick(state: .running, live: true) }   // thinking
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement()
        .accessibilityLabel("\(steps.filter { $0.state == .done }.count) of \(steps.count) steps done")
    }
}

struct Tick: View {
    let state: Step.State
    let live: Bool
    @State private var pulse = false
    var body: some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(fill)
            .overlay(RoundedRectangle(cornerRadius: 1.5).strokeBorder(state == .pending ? Color.secondary.opacity(0.5) : .clear, lineWidth: 1))
            .frame(width: 5, height: 12)
            .opacity(state == .running && live ? (pulse ? 0.35 : 1) : 1)
            .animation(state == .running && live ? .easeInOut(duration: 0.7).repeatForever(autoreverses: true) : .default, value: pulse)
            .onAppear { pulse = true }
    }
    private var fill: Color {
        switch state {
        case .done: Color.limeText.opacity(0.75)
        case .running: Color.lime
        case .failed: Color.red
        case .pending: Color.clear
        }
    }
}

// MARK: - Permission / question cards

struct PermissionCard: View {
    let model = AppModel.shared
    let request: PendingRequest
    let host: String

    var body: some View {
        let isPlan = request.tool == "ExitPlanMode"
        VStack(alignment: .leading, spacing: 10) {
            Text(summary)
                .font(.system(size: 12, design: .monospaced))
                .lineLimit(isPlan ? 12 : 5)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            HStack(spacing: 8) {
                PillButton(isPlan ? "Approve" : "Allow", prominent: true) { model.decide(request.sessionId, .allow(nil)) }
                PillButton(isPlan ? "Keep planning" : "Deny") { model.decide(request.sessionId, .deny) }
                PillButton("In \(host)") { model.decide(request.sessionId, .passthrough) }
                    .help("Answer with Claude Code's own prompt — e.g. to pick “always allow”")
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var summary: String {
        let i = request.input
        switch request.tool {
        case "Bash": return "Bash: \(i["command"] as? String ?? "")"
        case "Edit", "MultiEdit", "Write", "Read", "NotebookEdit":
            return "\(request.tool): \(i["file_path"] as? String ?? i["notebook_path"] as? String ?? "")"
        case "WebFetch": return "Fetch: \(i["url"] as? String ?? "")"
        case "ExitPlanMode": return i["plan"] as? String ?? "Plan ready"
        default:
            let json = (try? JSONSerialization.data(withJSONObject: i, options: [.sortedKeys, .withoutEscapingSlashes]))
                .map { String(decoding: $0, as: UTF8.self) } ?? ""
            return "\(Transcript.describe(request.tool, i)): \(json.prefix(400))"
        }
    }
}

struct QuestionCard: View {
    let model = AppModel.shared
    let request: PendingRequest
    let host: String
    @State private var picks: [Int: Set<String>] = [:]
    @State private var other: [Int: String] = [:]

    var body: some View {
        let questions = request.questions
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(questions.enumerated()), id: \.offset) { qi, q in
                question(qi, q)
            }
            HStack(spacing: 8) {
                PillButton("Send", prominent: canSend(questions)) { send(questions) }
                    .disabled(!canSend(questions))
                PillButton("Type in \(host)") { model.decide(request.sessionId, .passthrough) }
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder private func question(_ qi: Int, _ q: [String: Any]) -> some View {
        let multi = q["multiSelect"] as? Bool ?? false
        VStack(alignment: .leading, spacing: 6) {
            if let h = q["header"] as? String, !h.isEmpty {
                Text(h.uppercased()).font(.system(size: 10.5, weight: .heavy)).foregroundStyle(.black)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.lime, in: RoundedRectangle(cornerRadius: 4))
            }
            Text(q["question"] as? String ?? "").font(.system(size: 13.5, weight: .bold)).fixedSize(horizontal: false, vertical: true)
            ForEach(Array((q["options"] as? [[String: Any]] ?? []).enumerated()), id: \.offset) { _, o in
                let label = o["label"] as? String ?? ""
                let on = picks[qi, default: []].contains(label)
                Button {
                    var set = multi ? picks[qi, default: []] : []
                    if on { set.remove(label) } else { set.insert(label) }
                    picks[qi] = set
                    if !multi { other[qi] = nil }
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: multi ? (on ? "checkmark.square.fill" : "square") : (on ? "largecircle.fill.circle" : "circle"))
                            .foregroundStyle(on ? Color.limeText : .secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(label).font(.system(size: 13, weight: .medium))
                            if let d = o["description"] as? String, !d.isEmpty {
                                Text(d).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(Color.primary.opacity(on ? 0.12 : 0.05), in: RoundedRectangle(cornerRadius: 8))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
            Field(placeholder: "Other…", text: Binding(get: { other[qi] ?? "" }, set: {
                other[qi] = $0
                if !multi && !$0.isEmpty { picks[qi] = [] }
            }))
            .font(.system(size: 12.5))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.12)))
        }
    }

    private func answer(_ qi: Int) -> String? {
        let text = (other[qi] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let chosen = Array(picks[qi, default: []]).sorted() + (text.isEmpty ? [] : [text])
        return chosen.isEmpty ? nil : chosen.joined(separator: ", ")
    }

    private func canSend(_ qs: [[String: Any]]) -> Bool { !qs.isEmpty && qs.indices.allSatisfy { answer($0) != nil } }

    private func send(_ qs: [[String: Any]]) {
        model.decide(request.sessionId, .allow(QuestionCard.answered(request.input, answers: qs.indices.map { answer($0) ?? "" })))
    }

    /// AskUserQuestion takes its answers as `answers: {questionText: label}` added to the unchanged input.
    static func answered(_ input: [String: Any], answers: [String]) -> [String: Any] {
        let qs = input["questions"] as? [[String: Any]] ?? []
        var out = input
        var map: [String: String] = [:]
        for (q, a) in zip(qs, answers) { map[q["question"] as? String ?? ""] = a }
        out["answers"] = map
        return out
    }
}

struct PillButton: View {
    let title: String
    var prominent = false
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled
    @State private var hover = false
    init(_ title: String, prominent: Bool = false, action: @escaping () -> Void) {
        self.title = title; self.prominent = prominent; self.action = action
    }
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12.5, weight: .bold))
                .lineLimit(1)
                .padding(.horizontal, 14).padding(.vertical, 6)
                .foregroundStyle(prominent ? Color.black : Color.primary)
                .background(prominent ? Color.lime.opacity(hover ? 0.85 : 1) : Color.primary.opacity(hover ? 0.16 : 0.1), in: Capsule())
                .opacity(enabled ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

// MARK: - Detail

struct DetailView: View {
    let model = AppModel.shared
    let session: Session

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                IconButton("chevron.left", label: "Back to all sessions") { model.selected = nil }
                ForEach(model.visible) { s in
                    Button { model.selected = s.id } label: {
                        Avatar(color: Avatar.palette[model.colorIndex(s.id)], mood: mood(s), size: 22)
                            .padding(2)
                            .background(s.id == session.id ? Color.primary.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                    .help(s.title)
                    .accessibilityLabel("Show \(s.title)")
                }
                Spacer(minLength: 4)
                IconButton("arrow.up.forward.square", label: "Open in \(session.host)") { Focus.open(session) }
            }
            .padding(.bottom, 8)

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 14) {
                    Avatar(color: Avatar.palette[model.colorIndex(session.id)], mood: mood(session), size: 46)
                    SessionSummary(session: session, large: true)
                }
                if let r = model.pending[session.id] {
                    if r.isQuestion { QuestionCard(request: r, host: session.host) } else { PermissionCard(request: r, host: session.host) }
                }
                Divider()
                Text("\(session.folder) · \(session.host)")
                    .font(.system(size: 11)).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                if let p = session.info.prompt, session.status != .idle {
                    Text("› " + Transcript.firstLine(p))
                        .font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary).lineLimit(2)
                }
                StepList(steps: session.info.todos.isEmpty ? session.info.steps : session.info.todos,
                         isTodos: !session.info.todos.isEmpty)
                if let cmd = session.info.lastCommand { TerminalBlock(command: cmd, output: session.info.lastOutput, running: session.info.commandRunning && session.status == .busy) }
                Composer(session: session)
            }
            .padding(14)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

struct StepList: View {
    let steps: [Step]
    let isTodos: Bool
    private let limit = 8

    var body: some View {
        let shown = steps.suffix(isTodos ? 50 : limit)
        VStack(alignment: .leading, spacing: 7) {
            if steps.count > shown.count {
                Text("+\(steps.count - shown.count) earlier").font(.system(size: 11)).foregroundStyle(.tertiary).padding(.leading, 28)
            }
            if steps.isEmpty { Text("No tool calls yet this turn").font(.system(size: 12)).foregroundStyle(.tertiary) }
            ForEach(shown) { step in
                HStack(spacing: 8) {
                    stateIcon(step.state).frame(width: 16)
                    if !isTodos { Image(systemName: icon(step.tool)).font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 14) }
                    Text(step.text)
                        .font(.system(size: 12.5, weight: step.state == .running ? .semibold : .regular))
                        .foregroundStyle(step.state == .done ? .secondary : .primary)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
        }
    }

    @ViewBuilder private func stateIcon(_ s: Step.State) -> some View {
        switch s {
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.secondary)
        case .failed: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        case .pending: Image(systemName: "circle").foregroundStyle(.tertiary)
        case .running: Spinner(size: 12)
        }
    }

    private func icon(_ tool: String) -> String {
        switch tool {
        case "Bash": "apple.terminal"
        case "Edit", "MultiEdit", "Write", "NotebookEdit": "pencil"
        case "Read": "doc.text"
        case "Grep", "Glob", "WebSearch": "magnifyingglass"
        case "WebFetch": "globe"
        case "Agent", "Task": "person.2"
        case "AskUserQuestion": "questionmark.bubble"
        default: "wrench.and.screwdriver"
        }
    }
}

struct TerminalBlock: View {
    let command: String
    let output: String?
    let running: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Terminal", systemImage: "apple.terminal")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
            Text("$ " + command)
                .font(.system(size: 12, design: .monospaced)).foregroundStyle(Color.limeText)
                .lineLimit(3).textSelection(.enabled)
            if running {
                Text("running…").font(.system(size: 11.5, design: .monospaced)).foregroundStyle(.secondary)
            } else if let out = output?.trimmingCharacters(in: .whitespacesAndNewlines), !out.isEmpty {
                Text(out.split(separator: "\n").suffix(3).joined(separator: "\n"))
                    .font(.system(size: 11.5, design: .monospaced)).foregroundStyle(.secondary)
                    .lineLimit(3).textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: - Empty / onboarding

struct EmptyState: View {
    let hiddenCount: Int
    var body: some View {
        VStack(spacing: 8) {
            Avatar(color: .secondary.opacity(0.5), mood: .idle, size: 40)
            Text(hiddenCount > 0 ? "All sessions hidden" : "No Claude Code sessions running")
                .font(.system(size: 13, weight: .semibold))
            Text(hiddenCount > 0 ? "They'll come back when something changes." : "Start `claude` in a terminal or open Claude Code in VS Code.")
                .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }
}

struct HookBanner: View {
    let model = AppModel.shared
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Answer permissions from here").font(.system(size: 12.5, weight: .bold))
            Text(error ?? "Adds a PermissionRequest hook to ~/.claude/settings.json so Allow, Deny and questions show up in AgentBuddy. Restart running sessions to pick it up.")
                .font(.system(size: 11.5)).foregroundStyle(error == nil ? Color.secondary : Color.red)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                PillButton("Enable", prominent: true) {
                    do { try HookInstaller.set(installed: true); model.hookInstalled = true }
                    catch { self.error = "Couldn't update settings.json: \(error.localizedDescription)" }
                }
                PillButton("Not now") { model.hookPromptDismissed = true }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.lime.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Send a prompt to the session. Busy sessions queue it, same as typing while Claude works.
struct Composer: View {
    let model = AppModel.shared
    let session: Session
    @State private var text = ""
    @State private var result: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Field(placeholder: session.status == .busy ? "Queue a message…" : "Message \(session.title)…", text: $text)
                    .font(.system(size: 13))
                    .focused($focused)
                    .onSubmit(send)
                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 20))
                        .foregroundStyle(text.isEmpty ? Color.secondary : Color.lime)
                }
                .buttonStyle(.plain)
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                .help("Send (⏎)")
                .accessibilityLabel("Send message")
            }
            .padding(.leading, 12).padding(.trailing, 6).padding(.vertical, 6)
            .background(Color.white.opacity(focused ? 0.12 : 0.07), in: Capsule())
            .overlay(Capsule().strokeBorder(focused ? Color.lime.opacity(0.6) : .clear))
            if let result {
                Text(result).font(.system(size: 11)).foregroundStyle(.secondary).transition(.opacity)
            } else if session.isEditor {
                Text("\(session.host) can't take typed input — AgentBuddy copies it and opens the window.")
                    .font(.system(size: 11)).foregroundStyle(.tertiary)
            }
        }
        .onChange(of: focused) { _, f in model.composing = f }
        .onDisappear { model.composing = false }
    }

    private func send() {
        let r = Focus.send(text, to: session)
        withAnimation { result = r.message }
        if r.typed { text = "" }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { withAnimation { result = nil } }
    }
}

/// Small breathing dot that marks a session as live.
struct LiveDot: View {
    @State private var on = false
    var body: some View {
        Circle().fill(Color.lime).frame(width: 6, height: 6)
            .opacity(on ? 0.35 : 1)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
            .accessibilityHidden(true)
    }
}

/// Plain text field. Screenshot renders can't draw AppKit-backed controls, so they get a look-alike placeholder.
struct Field: View {
    let placeholder: String
    @Binding var text: String
    var body: some View {
        if Snapshot.active {
            Text(placeholder).foregroundStyle(.tertiary).frame(maxWidth: .infinity, alignment: .leading)
        } else {
            TextField(placeholder, text: $text).textFieldStyle(.plain)
        }
    }
}

/// Lime arc spinner — SwiftUI-only, so it matches the palette (and renders in screenshots).
struct Spinner: View {
    var size: CGFloat = 12
    @State private var spin = false
    var body: some View {
        Circle().trim(from: 0.15, to: 0.85)
            .stroke(Color.lime, style: StrokeStyle(lineWidth: size / 6, lineCap: .round))
            .frame(width: size, height: size)
            .rotationEffect(.degrees(spin ? 360 : 0))
            .animation(.linear(duration: 0.9).repeatForever(autoreverses: false), value: spin)
            .onAppear { spin = true }
            .accessibilityLabel("Running")
    }
}
