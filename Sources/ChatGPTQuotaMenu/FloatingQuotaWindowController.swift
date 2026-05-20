import AppKit
import SwiftUI

@MainActor
final class FloatingQuotaWindowController: NSObject, NSWindowDelegate {
    private let viewModel: QuotaViewModel
    private var panel: NSPanel?
    private let frameKey = "floatingQuotaWindowFrame"

    init(viewModel: QuotaViewModel) {
        self.viewModel = viewModel
        super.init()
    }

    var isVisible: Bool {
        panel?.isVisible == true
    }

    func show() {
        let panel = panel ?? makePanel()
        self.panel = panel
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: false)
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    func windowDidMove(_ notification: Notification) {
        saveFrame()
    }

    func windowDidResize(_ notification: Notification) {
        saveFrame()
    }

    private func makePanel() -> NSPanel {
        let savedFrame = UserDefaults.standard.string(forKey: frameKey)
            .flatMap(NSRectFromString)

        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let defaultFrame = NSRect(
            x: screenFrame.maxX - 260,
            y: screenFrame.maxY - 170,
            width: 232,
            height: 116
        )

        let panel = NSPanel(
            contentRect: savedFrame ?? defaultFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.delegate = self
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true

        let hostingView = MovableHostingView(rootView: FloatingQuotaView(viewModel: viewModel))
        hostingView.frame = NSRect(x: 0, y: 0, width: 232, height: 116)
        panel.contentView = hostingView
        return panel
    }

    private func saveFrame() {
        guard let panel else {
            return
        }
        UserDefaults.standard.set(NSStringFromRect(panel.frame), forKey: frameKey)
    }
}

private final class MovableHostingView<Content: View>: NSHostingView<Content> {
    override var mouseDownCanMoveWindow: Bool {
        true
    }
}

private struct FloatingQuotaView: View {
    @ObservedObject var viewModel: QuotaViewModel

    var body: some View {
        VStack(spacing: 6) {
            FloatingQuotaRow(snapshot: snapshot(.shortWindow), title: "5小时", showsDate: false)
            Divider()
                .opacity(0.28)
            FloatingQuotaRow(snapshot: snapshot(.weeklyThinking), title: "一周", showsDate: true, showsPaceHint: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 246, height: 132)
        .background(.ultraThinMaterial.opacity(0.78), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(.white.opacity(0.22), lineWidth: 1)
        )
    }

    private func snapshot(_ window: QuotaWindow) -> QuotaSnapshot? {
        viewModel.state.snapshots.first(where: { $0.window == window })
    }
}

private struct FloatingQuotaRow: View {
    let snapshot: QuotaSnapshot?
    let title: String
    let showsDate: Bool
    var showsPaceHint = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 10) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .leading)

                Text(snapshot?.displayAmount ?? "--")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Spacer(minLength: 6)

                VStack(alignment: .trailing, spacing: 2) {
                    Text("重置")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                    Text(resetText)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            if showsPaceHint {
                Text(paceHint)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(paceHintColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.leading, 54)
            }
        }
    }

    private var resetText: String {
        guard let resetAt = snapshot?.resetAt else {
            return "--"
        }
        if showsDate {
            return resetAt.formatted(.dateTime.month(.abbreviated).day().hour().minute())
        }
        return resetAt.formatted(date: .omitted, time: .shortened)
    }

    private var paceHint: String {
        guard let snapshot,
              let remaining = snapshot.remaining,
              let resetAt = snapshot.resetAt else {
            return "节奏未知"
        }

        let remainingPercent = Double(remaining)
        let totalWindowSeconds: TimeInterval = 7 * 24 * 60 * 60
        let remainingSeconds = max(0, min(totalWindowSeconds, resetAt.timeIntervalSinceNow))
        let timeProgress = 1 - remainingSeconds / totalWindowSeconds
        let usedProgress = 1 - remainingPercent / 100
        let paceDeltaPercent = (usedProgress - timeProgress) * 100

        if remainingPercent <= 20, paceDeltaPercent <= 5 {
            return "抓紧花！赶快薅羊毛！"
        }
        if paceDeltaPercent <= 5 {
            return "放心花！节奏正常"
        }
        if paceDeltaPercent <= 15 {
            return "稍微悠着点，使用进度已超时间\(Int(paceDeltaPercent.rounded()))%"
        }
        if paceDeltaPercent <= 30 {
            return "要省着点花啦，使用进度已超时间\(Int(paceDeltaPercent.rounded()))%"
        }
        return "真的得收着用了！花完警告！"
    }

    private var paceHintColor: Color {
        guard let snapshot,
              let remaining = snapshot.remaining,
              let resetAt = snapshot.resetAt else {
            return .secondary
        }

        let remainingPercent = Double(remaining)
        let totalWindowSeconds: TimeInterval = 7 * 24 * 60 * 60
        let remainingSeconds = max(0, min(totalWindowSeconds, resetAt.timeIntervalSinceNow))
        let timeProgress = 1 - remainingSeconds / totalWindowSeconds
        let usedProgress = 1 - remainingPercent / 100
        let paceDeltaPercent = (usedProgress - timeProgress) * 100

        if remainingPercent <= 20, paceDeltaPercent <= 5 {
            return .green
        }
        if paceDeltaPercent <= 5 {
            return .green
        }
        if paceDeltaPercent <= 15 {
            return .orange
        }
        return .red
    }
}
