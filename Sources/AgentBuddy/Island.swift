import SwiftUI

/// Geometry of the (real or virtual) notch the island hangs from.
struct NotchMetrics: Equatable {
    var width: CGFloat = 200
    var height: CGFloat = 32
    var hasNotch = false

    static func of(_ screen: NSScreen) -> NotchMetrics {
        let top = screen.safeAreaInsets.top
        if top > 0, let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea {
            return NotchMetrics(width: screen.frame.width - l.width - r.width, height: top, hasNotch: true)
        }
        // No notch: hang a slim pill under the menu bar's centre instead.
        return NotchMetrics(width: 170, height: max(24, NSStatusBar.system.thickness), hasNotch: false)
    }
}

/// Black shape with flared top corners (blends into the bezel) and rounded bottom corners. Both radii animate.
struct NotchShape: Shape {
    var top: CGFloat
    var bottom: CGFloat
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(top, bottom) }
        set { top = newValue.first; bottom = newValue.second }
    }
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.minX + top, y: r.minY + top), control: CGPoint(x: r.minX + top, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + top, y: r.maxY - bottom))
        p.addQuadCurve(to: CGPoint(x: r.minX + top + bottom, y: r.maxY), control: CGPoint(x: r.minX + top, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - top - bottom, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.maxX - top, y: r.maxY - bottom), control: CGPoint(x: r.maxX - top, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - top, y: r.minY + top))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: r.maxX - top, y: r.minY))
        p.closeSubpath()
        return p
    }
}

struct IslandView: View {
    let model = AppModel.shared
    var notch: NotchMetrics
    var maxHeight: CGFloat = 640
    @State private var contentHeight: CGFloat = 0

    static let expandedWidth: CGFloat = 460
    static let spring = Animation.spring(response: 0.42, dampingFraction: 0.86)
    private let flare: CGFloat = 8

    var body: some View {
        let open = model.expanded
        let n = min(model.visible.count, 3)
        let wing: CGFloat = model.sessions.isEmpty ? 0 : 20 + CGFloat(n) * 20 + (model.visible.count > 3 ? 20 : 0)
        let width = open ? Self.expandedWidth : notch.width + wing * 2
        let height = open ? min(maxHeight, notch.height + contentHeight) : notch.height
        ZStack(alignment: .top) {
            NotchShape(top: flare, bottom: open ? 24 : 12)
                .fill(.black)
                .shadow(color: .black.opacity(open ? 0.45 : 0), radius: 18, y: 8)
            VStack(spacing: 0) {
                topBar(open: open)
                    .frame(height: notch.height)
                expandedContent
                    .frame(height: open ? max(0, height - notch.height) : 0, alignment: .top)
                    .opacity(open ? 1 : 0)
                    .blur(radius: open ? 0 : 8)
                    .scaleEffect(open ? 1 : 0.94, anchor: .top)
                    .clipped()
            }
            .padding(.horizontal, flare)
        }
        .frame(width: width + flare * 2, height: height)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { model.islandSize = $0 }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
        .animation(Self.spring, value: open)
        .animation(Self.spring, value: contentHeight)
        .animation(Self.spring, value: model.sessions.isEmpty)
    }

    // MARK: top bar — sits beside the notch

    @ViewBuilder private func topBar(open: Bool) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                if open {
                    StatusDot()
                    Text("AgentBuddy").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                        .lineLimit(1).fixedSize()
                } else {
                    MiniAvatars()
                }
            }
            .padding(.leading, open ? 16 : 12)
            Spacer(minLength: notch.hasNotch ? notch.width : 8)
            HStack(spacing: 4) {
                if open {
                    IconButton(model.muted ? "speaker.slash" : "speaker.wave.2", label: model.muted ? "Unmute sounds" : "Mute sounds") {
                        model.muted.toggle()
                    }
                    IconButton(model.pinned ? "pin.fill" : "pin", label: model.pinned ? "Unpin — close when the pointer leaves" : "Keep open") {
                        model.pinned.toggle()
                    }
                    IconButton("chevron.up", label: "Close (Esc)") {
                        withAnimation(Self.spring) { model.close() }
                    }
                } else {
                    CollapsedBadge()
                }
            }
            .padding(.trailing, open ? 12 : 12)
        }
        .contentShape(Rectangle())
        .onTapGesture { if !open { withAnimation(Self.spring) { model.pinned = true } } }   // click the pill to open
    }

    // MARK: expanded body

    @ViewBuilder private var expandedContent: some View {
        let inner = Group {
                if let id = model.selected, let s = model.sessions.first(where: { $0.id == id }) {
                    DetailView(session: s)
                        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
                } else {
                    list.transition(.opacity)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 4)
            .padding(.bottom, 12)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            .animation(Self.spring, value: model.selected)
        // only scroll when it doesn't fit — keeps the common case a plain, cheap stack
        if notch.height + contentHeight > maxHeight {
            ScrollView { inner }.scrollIndicators(.automatic)
        } else {
            inner
        }
    }

    private var list: some View {
        let rows = model.visible
        let groups: [(String, [Session])] = [
            ("Needs you", rows.filter { model.needsYou($0) }),
            ("Working", rows.filter { !model.needsYou($0) && $0.status == .busy }),
            ("Idle", rows.filter { !model.needsYou($0) && $0.status != .busy }),
        ].filter { !$0.1.isEmpty }
        return VStack(alignment: .leading, spacing: 6) {
            if rows.isEmpty { EmptyState(hiddenCount: model.sessions.count) }
            ForEach(groups, id: \.0) { title, sessions in
                if groups.count > 1 {
                    Text("\(title) · \(sessions.count)".uppercased())
                        .font(.system(size: 10.5, weight: .bold)).tracking(0.6)
                        .foregroundStyle(title == "Needs you" ? Color.limeText : .secondary)
                        .padding(.leading, 6).padding(.top, title == groups.first?.0 ? 0 : 8)
                }
                ForEach(sessions) { s in
                    SessionRow(session: s)
                        .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                }
            }
            if !model.hookInstalled && !model.hookPromptDismissed { HookBanner() }
        }
        .animation(Self.spring, value: rows.map(\.id))
    }
}

/// Up to three robots in the left wing; ones that need you come first.
struct MiniAvatars: View {
    let model = AppModel.shared
    var body: some View {
        HStack(spacing: 3) {
            ForEach(model.visible.prefix(3)) { s in
                Avatar(color: Avatar.palette[model.colorIndex(s.id)], mood: mood(s), size: 17)
                    .help(s.title)
            }
            if model.visible.count > 3 {
                Text("+\(model.visible.count - 3)").font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.6))
            }
        }
    }
}

/// Right wing: what needs you, else how many are working.
struct CollapsedBadge: View {
    let model = AppModel.shared
    var body: some View {
        let attention = model.attentionCount, busy = model.busyCount
        HStack(spacing: 5) {
            if attention > 0 {
                StatusDot()
                Text("\(attention)").foregroundStyle(.orange)
            } else if busy > 0 {
                Spinner(size: 11)
                Text("\(busy)").foregroundStyle(Color.lime)
            } else if !model.sessions.isEmpty {
                Image(systemName: "moon.zzz.fill").font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
                Text("\(model.visible.count)").foregroundStyle(.white.opacity(0.55))
            }
        }
        .font(.system(size: 12, weight: .bold).monospacedDigit())
        .contentTransition(.numericText())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(attention > 0 ? "\(attention) sessions need you" : "\(busy) sessions working")
    }
}
