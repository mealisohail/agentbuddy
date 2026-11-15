import AppKit
import ServiceManagement
import SwiftUI

if CommandLine.arguments.contains("--hook") { HookBridge.runHook() }
if CommandLine.arguments.contains("--version") { print("AgentBuddy \(appVersion)"); exit(0) }
if CommandLine.arguments.contains("--uninstall-hook") {
    do { try HookInstaller.set(installed: false); print("Removed the AgentBuddy hook from ~/.claude/settings.json") }
    catch { print("Couldn't update ~/.claude/settings.json: \(error.localizedDescription)"); exit(1) }
    exit(0)
}

var appVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev" }
if CommandLine.arguments.contains("--selftest") { SelfTest.run() }
if CommandLine.arguments.contains("--snapshot") { MainActor.assumeIsolated { Snapshot.run() } }

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)   // menu-bar app: no Dock icon
    app.run()
}

/// Transparent, fixed-size window over the notch. It never resizes — only the SwiftUI island inside animates —
/// and it ignores the mouse everywhere outside the island so the menu bar and apps below stay clickable.
final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { true }   // lets the "Other…" answer field take typing

    /// A menu-bar app has no Edit menu, and that menu is what normally turns ⌘V/⌘C/⌘X/⌘A/⌘Z into actions.
    /// Without this, paste, copy and undo do nothing in the message and "Other…" fields.
    override func performKeyEquivalent(with e: NSEvent) -> Bool {
        if let sel = Self.editAction(flags: e.modifierFlags, key: e.charactersIgnoringModifiers ?? ""),
           NSApp.sendAction(sel, to: nil, from: self) { return true }
        return super.performKeyEquivalent(with: e)
    }

    static func editAction(flags: NSEvent.ModifierFlags, key: String) -> Selector? {
        switch (flags.intersection(.deviceIndependentFlagsMask).subtracting(.capsLock), key.lowercased()) {
        case (.command, "x"): #selector(NSText.cut(_:))
        case (.command, "c"): #selector(NSText.copy(_:))
        case (.command, "v"): #selector(NSText.paste(_:))
        case (.command, "a"): #selector(NSText.selectAll(_:))
        case (.command, "z"): Selector(("undo:"))
        case ([.command, .shift], "z"): Selector(("redo:"))
        default: nil
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel.shared
    var panel: IslandPanel!
    var statusItem: NSStatusItem!
    var hoverWork: DispatchWorkItem?
    var hoverTarget: Bool?          // what the scheduled hoverWork will set
    var peekWork: DispatchWorkItem?
    var monitors: [Any] = []

    func applicationDidFinishLaunching(_ note: Notification) {
        guard HookBridge.startServer() else {
            NSApp.terminate(nil)        // another copy already owns the socket
            return
        }
        if model.hookInstalled && !HookInstaller.pointsHere {
            try? HookInstaller.set(installed: true)     // app moved or renamed: repoint the hook at this copy
        }
        makePanel()
        makeStatusItem()
        model.onAttention = { [weak self] in self?.peek() }
        model.start()
        observe()
        trackMouse()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { (NSApp.delegate as? AppDelegate)?.placePanel() }
        }
    }

    // MARK: island window

    var screen: NSScreen {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    func makePanel() {
        panel = IslandPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar + 1                  // above the menu bar, like the system's own notch UI
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false                       // the island draws its own
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = true
        placePanel()
        panel.orderFrontRegardless()
    }

    func placePanel() {
        let s = screen
        let height = min(720, s.frame.height * 0.8)
        let width = IslandView.expandedWidth + 80     // room for the shadow
        panel.setFrame(NSRect(x: s.frame.midX - width / 2, y: s.frame.maxY - height, width: width, height: height), display: true)
        panel.contentView = NSHostingView(rootView: IslandView(notch: .of(s), maxHeight: height - 30))
    }

    /// The island's current rect in screen coordinates (it's top-centred in the panel).
    var islandRect: NSRect {
        let size = model.islandSize
        return NSRect(x: panel.frame.midX - size.width / 2, y: panel.frame.maxY - size.height, width: size.width, height: size.height)
    }

    func trackMouse() {
        let handler: (NSEvent) -> Void = { _ in MainActor.assumeIsolated { (NSApp.delegate as? AppDelegate)?.mouseMoved() } }
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: handler) as Any)
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { e in handler(e); return e } as Any)
        // click anywhere else closes it, like a popover
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
            MainActor.assumeIsolated {
                guard let d = NSApp.delegate as? AppDelegate, d.model.expanded,
                      !d.islandRect.contains(NSEvent.mouseLocation) else { return }
                withAnimation(IslandView.spring) { d.model.close() }
            }
        } as Any)
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            guard e.keyCode == 53 else { return e }     // Esc: back out of detail, then close
            MainActor.assumeIsolated {
                guard let d = NSApp.delegate as? AppDelegate else { return }
                withAnimation(IslandView.spring) {
                    if d.model.selected != nil { d.model.selected = nil } else { d.model.close() }
                }
            }
            return nil
        } as Any)
        // the island also changes size under a still pointer
        Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
            MainActor.assumeIsolated { (NSApp.delegate as? AppDelegate)?.mouseMoved() }
        }
    }

    func mouseMoved() {
        let inside = islandRect.insetBy(dx: -6, dy: -6).contains(NSEvent.mouseLocation)
        panel.ignoresMouseEvents = !inside
        if !inside { model.suppressHover = false }
        let want = inside && !model.suppressHover
        if want == model.hovering { hoverWork?.cancel(); hoverTarget = nil; return }
        if hoverTarget == want { return }      // already counting down — don't restart it on every event
        hoverTarget = want
        hoverWork?.cancel()
        // small intent delay on open, a forgiving one on close, so passing the pointer through doesn't flicker it
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.hoverTarget = nil
            withAnimation(IslandView.spring) {
                self.model.hovering = want
                if !self.model.expanded { self.model.selected = nil }
            }
        }
        hoverWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (want ? 0.12 : 0.45), execute: work)
    }

    /// Open for a few seconds when a session needs you; stays open if the pointer moves onto it.
    func peek() {
        withAnimation(IslandView.spring) { model.peeking = true }
        peekWork?.cancel()
        let work = DispatchWorkItem { [weak self] in withAnimation(IslandView.spring) { self?.model.peeking = false } }
        peekWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: work)
    }

    // MARK: menu bar

    func makeStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = Self.robotIcon()
        statusItem.button?.imagePosition = .imageLeading
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem.button?.setAccessibilityLabel("AgentBuddy")
    }

    @objc func statusClicked() {
        let e = NSApp.currentEvent
        if e?.type == .rightMouseUp || e?.modifierFlags.contains(.control) == true { showMenu() }
        else { togglePinned() }
    }

    func showMenu() {
        let m = NSMenu()
        m.addItem(withTitle: model.expanded ? "Close AgentBuddy" : "Open AgentBuddy", action: #selector(togglePinned), keyEquivalent: "").target = self
        m.addItem(.separator())
        add(m, "Mute Sounds", model.muted, #selector(toggleMute))
        add(m, "Answer Permissions in AgentBuddy", model.holdPermissions && model.hookInstalled, #selector(toggleHold))
        add(m, "Launch at Login", SMAppService.mainApp.status == .enabled, #selector(toggleLogin))
        if model.hookInstalled {
            m.addItem(withTitle: "Remove Claude Code Hook", action: #selector(removeHook), keyEquivalent: "").target = self
        }
        m.addItem(.separator())
        m.addItem(withTitle: "AgentBuddy \(appVersion)", action: nil, keyEquivalent: "")
        m.addItem(withTitle: "Quit AgentBuddy", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = m
        statusItem.button?.performClick(nil)
        statusItem.menu = nil      // keep left-click toggling the island
    }

    private func add(_ m: NSMenu, _ title: String, _ on: Bool, _ sel: Selector) {
        let item = m.addItem(withTitle: title, action: sel, keyEquivalent: "")
        item.target = self
        item.state = on ? .on : .off
    }

    @objc func togglePinned() {
        withAnimation(IslandView.spring) { if model.expanded { model.close() } else { model.pinned = true } }
    }
    @objc func toggleMute() { model.muted.toggle() }

    @objc func toggleHold() {
        if !model.hookInstalled {
            do { try HookInstaller.set(installed: true); model.hookInstalled = true; model.holdPermissions = true }
            catch { alert("Couldn't update ~/.claude/settings.json", error.localizedDescription) }
        } else {
            model.holdPermissions.toggle()
        }
    }

    @objc func removeHook() {
        do { try HookInstaller.set(installed: false); model.hookInstalled = false }
        catch { alert("Couldn't update ~/.claude/settings.json", error.localizedDescription) }
    }

    @objc func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch {
            alert("Couldn't change Launch at Login", "\(error.localizedDescription)\n\nMove AgentBuddy into Applications and try again.")
        }
    }

    func alert(_ title: String, _ text: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        NSApp.activate()
        a.runModal()
    }

    /// Keeps the menu bar badge in sync — the only indicator on displays without a notch-sized gap.
    func observe() {
        withObservationTracking {
            let attention = model.attentionCount
            let busy = model.busyCount
            let total = model.sessions.count
            let title = NSMutableAttributedString()
            let font = NSFont.menuBarFont(ofSize: 0)
            if attention > 0 {
                title.append(NSAttributedString(string: " ●\(attention)", attributes: [.foregroundColor: NSColor.systemOrange, .font: font]))
            } else if total > 0 {
                title.append(NSAttributedString(string: " \(busy > 0 ? busy : total)", attributes: [.font: font]))
            }
            statusItem.button?.attributedTitle = title
            statusItem.button?.toolTip = "AgentBuddy — \(total) sessions, \(busy) working, \(attention) need you"
        } onChange: {
            DispatchQueue.main.async { MainActor.assumeIsolated { (NSApp.delegate as? AppDelegate)?.observe() } }
        }
    }

    static func robotIcon() -> NSImage {
        let img = NSImage(size: NSSize(width: 16, height: 16), flipped: true) { _ in
            NSColor.black.setFill()
            let body = NSBezierPath(roundedRect: NSRect(x: 2, y: 1, width: 12, height: 11), xRadius: 3, yRadius: 3)
            body.append(NSBezierPath(rect: NSRect(x: 4, y: 12, width: 2.5, height: 3)))
            body.append(NSBezierPath(rect: NSRect(x: 9.5, y: 12, width: 2.5, height: 3)))
            body.fill()
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(rect: NSRect(x: 5, y: 4, width: 2, height: 3)).fill()
            NSBezierPath(rect: NSRect(x: 9, y: 4, width: 2, height: 3)).fill()
            NSBezierPath(rect: NSRect(x: 5.5, y: 8.5, width: 5, height: 1.3)).fill()
            return true
        }
        img.isTemplate = true
        return img
    }
}
