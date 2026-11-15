import Foundation

/// oh-my-pi (`omp`) support. omp keeps no live status file, so AgentBuddy drops a small extension into
/// ~/.omp/agent/extensions that mirrors each session's state into ~/.agentbuddy/omp/<pid>.json.
/// omp's approval prompts can be watched but not answered by an extension, so these sessions show
/// "needs you" and jump to their terminal instead of offering Allow/Deny.
enum Omp {
    static let home = FileManager.default.homeDirectoryForCurrentUser
    static var agentDir: URL {
        if let d = ProcessInfo.processInfo.environment["PI_CODING_AGENT_DIR"], !d.isEmpty { return URL(fileURLWithPath: d) }
        return home.appendingPathComponent(".omp/agent")
    }
    static var extensionFile: URL { agentDir.appendingPathComponent("extensions/agentbuddy.ts") }
    static var stateDir: URL { home.appendingPathComponent(".agentbuddy/omp") }

    /// Installs or updates the extension when omp is set up on this Mac. omp loads it on its next start.
    static func installExtension() {
        guard FileManager.default.fileExists(atPath: agentDir.path) else { return }
        let data = Data(extensionSource.utf8)
        if (try? Data(contentsOf: extensionFile)) == data { return }
        try? FileManager.default.createDirectory(at: extensionFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: extensionFile, options: .atomic)
    }

    static func removeExtension() {
        try? FileManager.default.removeItem(at: extensionFile)
    }

    /// Live omp sessions from the extension's state files; files of exited processes are removed.
    static func sessions(alive: (pid_t) -> Bool = { Omp.isAlive($0) }) -> [Session] {
        let files = (try? FileManager.default.contentsOfDirectory(at: stateDir, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.compactMap { f in
            guard let data = try? Data(contentsOf: f),
                  let d = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = d["sessionId"] as? String, let pid = d["pid"] as? Int, let cwd = d["cwd"] as? String else { return nil }
            guard alive(pid_t(pid)) else { try? FileManager.default.removeItem(at: f); return nil }
            return session(from: d, id: id, pid: pid_t(pid), cwd: cwd)
        }
    }

    static func session(from d: [String: Any], id: String, pid: pid_t, cwd: String) -> Session {
        let status: Session.Status = switch d["status"] as? String {
            case "busy": .busy
            case "waiting": .waiting
            default: .idle
        }
        let ms = { (k: String) in (d[k] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) } }
        var s = Session(id: id, pid: pid, cwd: cwd, entrypoint: "omp", name: d["title"] as? String,
                        startedAt: d["startedAt"] as? Double ?? 0, status: status,
                        waitingFor: d["waitingFor"] as? String, statusSince: ms("statusUpdatedAt") ?? Date())
        s.tmux = d["tmux"] as? String
        s.info.title = d["title"] as? String
        s.info.prompt = d["prompt"] as? String
        s.info.turnStart = ms("turnStart")
        s.info.lastActivity = ms("statusUpdatedAt")
        s.info.lastCommand = d["lastCommand"] as? String
        s.info.commandRunning = d["commandRunning"] as? Bool ?? false
        s.info.steps = (d["steps"] as? [[String: Any]] ?? []).compactMap { st in
            guard let sid = st["id"] as? String, let tool = st["tool"] as? String, let text = st["text"] as? String else { return nil }
            let state: Step.State = switch st["state"] as? String {
                case "done": .done
                case "failed": .failed
                default: .running
            }
            return Step(id: sid, tool: tool, text: text, state: state)
        }
        return s
    }

    /// The pid exists and is still omp (compiled binary) or the bun/node running it, not a reused pid.
    static func isAlive(_ pid: pid_t) -> Bool {
        guard kill(pid, 0) == 0 || errno == EPERM else { return false }
        var buf = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 else { return true }
        let path = String(cString: buf).lowercased()
        return path.hasSuffix("/omp") || path.hasSuffix("/bun") || path.hasSuffix("/node")
    }

    /// Loaded by omp with Bun. Keep it dependency-free: it only writes one JSON file per process.
    static let extensionSource = #"""
// AgentBuddy for oh-my-pi. Installed and updated by AgentBuddy.app; deleting AgentBuddy removes it.
// Mirrors this session's state into ~/.agentbuddy/omp/<pid>.json so the notch app can show it.
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { spawnSync } from "node:child_process";

const TOOLS: Record<string, string> = { bash: "Bash", read: "Read", edit: "Edit", write: "Write", grep: "Grep", glob: "Glob", find: "Glob", task: "Task" };

function label(tool: string, args: any, intent?: string): string {
	const a = args && typeof args === "object" ? args : {};
	if (tool === "Bash" && typeof a.command === "string") return intent || `Run ${a.command.split("\n")[0].slice(0, 70)}`;
	if (intent) return intent;
	const p = a.path ?? a.file_path ?? (Array.isArray(a.paths) ? a.paths[0] : undefined);
	if (typeof p === "string") return `${tool} ${path.basename(p)}`;
	if (typeof a.pattern === "string") return `${tool} ${a.pattern.slice(0, 60)}`;
	return tool;
}

export default function agentbuddy(pi: any) {
	if (process.env.AGENTBUDDY_DISABLED === "1") return;
	const dir = path.join(os.homedir(), ".agentbuddy", "omp");
	const file = path.join(dir, `${process.pid}.json`);
	const now = () => Date.now();
	const s: any = { pid: process.pid, cwd: process.cwd(), startedAt: now(), status: "idle", statusUpdatedAt: now(), steps: [] };
	if (process.env.TMUX_PANE) {
		try {
			const out = spawnSync("tmux", ["display-message", "-p", "-t", process.env.TMUX_PANE, "#{session_name}:#{window_id}.#{pane_id}"]);
			s.tmux = out.stdout?.toString().trim() || undefined;
		} catch {}
	}

	const write = (ctx?: any) => {
		try {
			if (ctx?.sessionManager) {
				s.sessionId = ctx.sessionManager.getSessionId?.() ?? s.sessionId;
				s.title = ctx.sessionManager.getSessionName?.() ?? s.title;
			}
			if (ctx?.cwd) s.cwd = ctx.cwd;
			if (!s.sessionId) return;
			fs.mkdirSync(dir, { recursive: true });
			fs.writeFileSync(`${file}.tmp`, JSON.stringify(s));
			fs.renameSync(`${file}.tmp`, file);
		} catch {}
	};
	const status = (st: string, waitingFor?: string) => {
		if (s.status !== st || s.waitingFor !== waitingFor) s.statusUpdatedAt = now();
		s.status = st;
		s.waitingFor = waitingFor;
	};
	const remove = () => { try { fs.rmSync(file, { force: true }); } catch {} };

	pi.on("session_start", (_e: any, ctx: any) => write(ctx));
	pi.on("session_switch", (_e: any, ctx: any) => { s.steps = []; s.prompt = undefined; write(ctx); });
	pi.on("input", (e: any, ctx: any) => {
		if (e?.source !== "interactive" || typeof e.text !== "string") return;
		s.prompt = e.text.slice(0, 500); s.steps = []; s.turnStart = now();
		write(ctx);
	});
	pi.on("agent_start", (_e: any, ctx: any) => { status("busy"); write(ctx); });
	pi.on("agent_end", (_e: any, ctx: any) => { status("idle"); s.commandRunning = false; write(ctx); });
	pi.on("tool_execution_start", (e: any, ctx: any) => {
		const tool = TOOLS[e.toolName] ?? e.toolName;
		s.steps.push({ id: e.toolCallId, tool, text: label(tool, e.args, e.intent), state: "running" });
		s.steps = s.steps.slice(-30);
		if (tool === "Bash" && typeof e.args?.command === "string") { s.lastCommand = e.args.command.slice(0, 300); s.commandRunning = true; }
		write(ctx);
	});
	pi.on("tool_execution_end", (e: any, ctx: any) => {
		const st = s.steps.find((x: any) => x.id === e.toolCallId);
		if (st) st.state = e.isError ? "failed" : "done";
		if (TOOLS[e.toolName] === "Bash") s.commandRunning = false;
		write(ctx);
	});
	pi.on("tool_approval_requested", (e: any, ctx: any) => { status("waiting", `approve ${TOOLS[e.toolName] ?? e.toolName}`); write(ctx); });
	pi.on("tool_approval_resolved", (_e: any, ctx: any) => { status("busy"); write(ctx); });
	pi.on("session_shutdown", remove);
	process.on("exit", remove);
}
"""#
}
