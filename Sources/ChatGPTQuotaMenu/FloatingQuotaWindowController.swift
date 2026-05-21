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
        let panelSize = NSSize(width: 320, height: 164)

        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let defaultFrame = NSRect(
            x: screenFrame.maxX - 260,
            y: screenFrame.maxY - 170,
            width: panelSize.width,
            height: panelSize.height
        )
        let restoredFrame = savedFrame.map {
            NSRect(origin: $0.origin, size: panelSize)
        }

        let panel = NSPanel(
            contentRect: restoredFrame ?? defaultFrame,
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
        hostingView.frame = NSRect(origin: .zero, size: panelSize)
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
        let data = FloatingQuotaData(
            short: snapshot(.shortWindow),
            weekly: snapshot(.weeklyThinking)
        )

        Group {
            switch viewModel.dialStyle {
            case .glass:
                GlassQuotaDial(data: data)
            case .casio:
                CasioQuotaDial(data: data)
            case .eink:
                EInkQuotaDial(data: data)
            }
        }
        .frame(width: 320, height: 164)
    }

    private func snapshot(_ window: QuotaWindow) -> QuotaSnapshot? {
        viewModel.state.snapshots.first(where: { $0.window == window })
    }
}

private struct FloatingQuotaData {
    let short: QuotaSnapshot?
    let weekly: QuotaSnapshot?

    var shortAmount: String { short?.displayAmount ?? "--" }
    var weeklyAmount: String { weekly?.displayAmount ?? "--" }
    var shortProgress: Double { progress(short) }
    var weeklyProgress: Double { progress(weekly) }
    var shortReset: String { resetText(short, showsDate: false) }
    var weeklyReset: String { resetText(weekly, showsDate: true) }

    var paceHint: String {
        guard let weekly,
              let remaining = weekly.remaining,
              let resetAt = weekly.resetAt else {
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

    var warningLevel: WarningLevel {
        guard let weekly,
              let remaining = weekly.remaining,
              let resetAt = weekly.resetAt else {
            return .neutral
        }

        let remainingPercent = Double(remaining)
        let totalWindowSeconds: TimeInterval = 7 * 24 * 60 * 60
        let remainingSeconds = max(0, min(totalWindowSeconds, resetAt.timeIntervalSinceNow))
        let timeProgress = 1 - remainingSeconds / totalWindowSeconds
        let usedProgress = 1 - remainingPercent / 100
        let paceDeltaPercent = (usedProgress - timeProgress) * 100

        if remainingPercent <= 20, paceDeltaPercent <= 5 {
            return .bonus
        }
        if paceDeltaPercent <= 5 {
            return .normal
        }
        if paceDeltaPercent <= 15 {
            return .caution
        }
        return .danger
    }

    private func progress(_ snapshot: QuotaSnapshot?) -> Double {
        guard let remaining = snapshot?.remaining else {
            return 0
        }
        return max(0, min(1, Double(remaining) / 100))
    }

    private func resetText(_ snapshot: QuotaSnapshot?, showsDate: Bool) -> String {
        guard let resetAt = snapshot?.resetAt else {
            return "--"
        }
        if showsDate {
            return resetAt.formatted(.dateTime.month(.abbreviated).day().hour().minute())
        }
        return resetAt.formatted(date: .omitted, time: .shortened)
    }
}

private enum WarningLevel {
    case neutral
    case normal
    case bonus
    case caution
    case danger

    var casioSkinName: String {
        switch self {
        case .neutral, .normal:
            return "casio-skin-normal"
        case .bonus:
            return "casio-skin-bonus"
        case .caution:
            return "casio-skin-caution"
        case .danger:
            return "casio-skin-danger"
        }
    }
}

private struct GlassQuotaDial: View {
    let data: FloatingQuotaData

    var body: some View {
        VStack(spacing: 6) {
            FloatingQuotaRow(snapshot: data.short, title: "5小时", showsDate: false)
            Divider()
                .opacity(0.28)
            FloatingQuotaRow(snapshot: data.weekly, title: "一周", showsDate: true, showsPaceHint: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial.opacity(0.78), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(.white.opacity(0.22), lineWidth: 1)
        )
    }
}

private struct CasioQuotaDial: View {
    let data: FloatingQuotaData

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size

            ZStack {
                CasioSkinImage(skinName: data.warningLevel.casioSkinName)
                    .frame(width: size.width, height: size.height)

                CasioQuotaOverlay(data: data)
                    .frame(width: size.width, height: size.height)
            }
        }
    }
}

private struct EInkQuotaDial: View {
    let data: FloatingQuotaData

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                EInkProgressRow(title: "5小时", amount: data.shortAmount, progress: data.shortProgress)
                EInkProgressRow(title: "一周", amount: data.weeklyAmount, progress: data.weeklyProgress)
                VStack(spacing: 6) {
                    EInkResetBlock(title: "5小时重置", value: data.shortReset)
                    EInkResetBlock(title: "一周重置", value: data.weeklyReset)
                }
                .frame(width: 66)
            }

            Text(data.paceHint)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .foregroundStyle(Color(hex: 0xF7F5EF))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(Color(hex: 0x222222), in: RoundedRectangle(cornerRadius: 4))
        }
        .padding(10)
        .background(Color(hex: 0xF1EFE7), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color(hex: 0x2A2A2A), lineWidth: 1)
        )
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

private struct CasioSkinImage: View {
    let skinName: String

    var body: some View {
        if let image = NSImage.casioSkin(named: skinName) {
            Image(nsImage: image)
                .resizable()
                .clipped()
        } else {
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(hex: 0x151719))
                .overlay(
                    Text("皮肤资源未加载")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.red)
                )
        }
    }
}

private struct CasioQuotaOverlay: View {
    let data: FloatingQuotaData
    private let showsLayoutFrames = false

    var body: some View {
        GeometryReader { proxy in
            let ink = Color(hex: 0x172017)
            let layout = CasioOverlayLayout(size: proxy.size)

            ZStack {
                CasioQuotaNumber(amount: data.shortAmount)
                    .foregroundStyle(ink)
                    .frame(in: layout.shortQuota)

                CasioQuotaNumber(amount: data.weeklyAmount)
                    .foregroundStyle(ink)
                    .frame(in: layout.weeklyQuota)

                CasioResetValue(value: data.shortReset)
                    .foregroundStyle(ink)
                    .frame(in: layout.shortReset)

                CasioWeeklyResetValue(value: data.weeklyReset)
                    .foregroundStyle(ink)
                    .frame(in: layout.weeklyReset)

                HStack(spacing: 9) {
                    LCDChineseText(data.paceHint, size: 11)
                }
                .foregroundStyle(Color(hex: 0x171108))
                .frame(in: layout.warning)

                if showsLayoutFrames {
                    CasioLayoutFrame(rect: layout.shortQuota, color: .cyan, label: "5小时数字")
                    CasioLayoutFrame(rect: layout.weeklyQuota, color: .cyan, label: "一周数字")
                    CasioLayoutFrame(rect: layout.shortReset, color: .green, label: "时间")
                    CasioLayoutFrame(rect: layout.weeklyReset, color: .green, label: "日期/时间")
                    CasioLayoutFrame(rect: layout.warning, color: .orange, label: "提醒")
                }
            }
        }
    }
}

private struct LCDChineseText: View {
    let text: String
    let size: CGFloat

    init(_ text: String, size: CGFloat) {
        self.text = text
        self.size = size
    }

    var body: some View {
        Text(text)
            .font(.custom("PingFang SC", size: size).weight(.black))
            .tracking(0.7)
            .lineLimit(1)
            .minimumScaleFactor(0.45)
            .fixedSize(horizontal: false, vertical: true)
            .scaleEffect(x: 0.92, y: 1, anchor: .center)
            .shadow(color: Color(hex: 0x171108).opacity(0.75), radius: 0, x: 0.45, y: 0)
            .shadow(color: Color(hex: 0x171108).opacity(0.55), radius: 0, x: -0.35, y: 0)
    }
}

private struct CasioOverlayLayout {
    let size: CGSize

    var shortQuota: CGRect {
        rect(x: 0.298, y: 0.162, width: 0.351, height: 0.252)
    }

    var weeklyQuota: CGRect {
        rect(x: 0.304, y: 0.475, width: 0.348, height: 0.253)
    }

    var shortReset: CGRect {
        rect(x: 0.704, y: 0.207, width: 0.164, height: 0.300)
    }

    var weeklyReset: CGRect {
        rect(x: 0.713, y: 0.555, width: 0.151, height: 0.201)
    }

    var warning: CGRect {
        rect(x: 0.176, y: 0.793, width: 0.681, height: 0.092)
    }

    private func rect(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> CGRect {
        CGRect(
            x: size.width * x,
            y: size.height * y,
            width: size.width * width,
            height: size.height * height
        )
    }
}

private struct CasioLayoutFrame: View {
    let rect: CGRect
    let color: Color
    let label: String

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .strokeBorder(color.opacity(0.92), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            .background(color.opacity(0.08))
            .overlay(alignment: .topLeading) {
                Text(label)
                    .font(.system(size: 6, weight: .bold))
                    .foregroundStyle(color)
                    .padding(.horizontal, 2)
                    .background(Color.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 2))
                    .offset(x: 2, y: 2)
            }
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .allowsHitTesting(false)
    }
}

private struct CasioQuotaNumber: View {
    let amount: String

    var body: some View {
        SevenSegmentText(amount.replacingOccurrences(of: "%", with: ""))
            .padding(.vertical, 2)
            .padding(.horizontal, 4)
        .clipped()
    }
}

private struct CasioResetValue: View {
    let value: String

    var body: some View {
        SevenSegmentText(value)
            .padding(.vertical, 1)
            .padding(.horizontal, 2)
            .clipped()
    }
}

private struct CasioWeeklyResetValue: View {
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(datePart)
                .font(.system(size: 8, weight: .black, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            SevenSegmentText(timePart)
                .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, 2)
        .clipped()
    }

    private var datePart: String {
        let parts = value.split(separator: " ", maxSplits: 1).map(String.init)
        return parts.first ?? value
    }

    private var timePart: String {
        let parts = value.split(separator: " ", maxSplits: 1).map(String.init)
        return parts.count > 1 ? parts[1] : "--"
    }
}

private struct EInkProgressRow: View {
    let title: String
    let amount: String
    let progress: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                Spacer(minLength: 2)
                Text(amount)
                    .font(.system(size: 22, weight: .heavy, design: .monospaced))
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
            }
            ProgressBar(progress: progress, fill: Color(hex: 0x222222), track: Color(hex: 0xD2D0C6), height: 6)
        }
        .foregroundStyle(Color(hex: 0x222222))
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color(hex: 0xB8B5AA), lineWidth: 1)
        )
    }
}

private struct EInkResetBlock: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(title)
                .font(.system(size: 9, weight: .medium))
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.58)
        }
        .foregroundStyle(Color(hex: 0x222222))
        .frame(maxWidth: .infinity, minHeight: 34, alignment: .trailing)
        .padding(.horizontal, 6)
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(Color(hex: 0xB8B5AA), lineWidth: 1)
        )
    }
}

private struct ProgressBar: View {
    let progress: Double
    let fill: Color
    let track: Color
    var height: CGFloat = 5

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(track)
                Capsule()
                    .fill(fill)
                    .frame(width: max(height, proxy.size.width * progress))
            }
        }
        .frame(height: height)
    }
}

private struct SevenSegmentText: View {
    private let characters: [Character]

    init(_ text: String) {
        self.characters = Array(text)
    }

    var body: some View {
        GeometryReader { proxy in
            let spacing: CGFloat = max(1, proxy.size.height * 0.06)
            let baseHeight = proxy.size.height
            let baseWidths = characters.map { glyphAspect(for: $0) * baseHeight }
            let totalSpacing = spacing * CGFloat(max(0, characters.count - 1))
            let totalBaseWidth = baseWidths.reduce(0, +) + totalSpacing
            let scale = min(1, proxy.size.width / max(1, totalBaseWidth))
            let glyphHeight = baseHeight * scale
            let glyphWidths = baseWidths.map { $0 * scale }
            let totalWidth = glyphWidths.reduce(0, +) + totalSpacing * scale

            HStack(alignment: .center, spacing: spacing * scale) {
                ForEach(Array(characters.enumerated()), id: \.offset) { index, character in
                    SevenSegmentGlyph(character: character)
                        .frame(width: glyphWidths[index], height: glyphHeight)
                }
            }
            .frame(width: totalWidth, height: glyphHeight)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .clipped()
    }

    private func glyphAspect(for character: Character) -> CGFloat {
        if character == ":" {
            return 0.28
        }
        if character == "%" {
            return 0.55
        }
        return 0.56
    }
}

private struct SevenSegmentGlyph: View {
    let character: Character

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let thickness = max(1.2, min(width, height) * 0.16)
            let segments = activeSegments(for: character)

            ZStack {
                if character == ":" {
                    Circle()
                        .frame(width: thickness * 1.15, height: thickness * 1.15)
                        .position(x: width / 2, y: height * 0.34)
                    Circle()
                        .frame(width: thickness * 1.15, height: thickness * 1.15)
                        .position(x: width / 2, y: height * 0.66)
                } else if character == "%" {
                    Text("%")
                        .font(.system(size: height * 0.84, weight: .black, design: .monospaced))
                        .minimumScaleFactor(0.8)
                        .frame(width: width, height: height)
                } else {
                    Segment(isActive: segments.contains(.top))
                        .frame(width: width * 0.64, height: thickness)
                        .position(x: width / 2, y: thickness / 2)
                    Segment(isActive: segments.contains(.middle))
                        .frame(width: width * 0.64, height: thickness)
                        .position(x: width / 2, y: height / 2)
                    Segment(isActive: segments.contains(.bottom))
                        .frame(width: width * 0.64, height: thickness)
                        .position(x: width / 2, y: height - thickness / 2)
                    Segment(isActive: segments.contains(.upperLeft))
                        .frame(width: thickness, height: height * 0.36)
                        .position(x: thickness / 2, y: height * 0.25)
                    Segment(isActive: segments.contains(.upperRight))
                        .frame(width: thickness, height: height * 0.36)
                        .position(x: width - thickness / 2, y: height * 0.25)
                    Segment(isActive: segments.contains(.lowerLeft))
                        .frame(width: thickness, height: height * 0.36)
                        .position(x: thickness / 2, y: height * 0.75)
                    Segment(isActive: segments.contains(.lowerRight))
                        .frame(width: thickness, height: height * 0.36)
                        .position(x: width - thickness / 2, y: height * 0.75)
                }
            }
        }
    }

    private func activeSegments(for character: Character) -> Set<SevenSegment> {
        switch character {
        case "0":
            return [.top, .upperLeft, .upperRight, .lowerLeft, .lowerRight, .bottom]
        case "1":
            return [.upperRight, .lowerRight]
        case "2":
            return [.top, .upperRight, .middle, .lowerLeft, .bottom]
        case "3":
            return [.top, .upperRight, .middle, .lowerRight, .bottom]
        case "4":
            return [.upperLeft, .upperRight, .middle, .lowerRight]
        case "5":
            return [.top, .upperLeft, .middle, .lowerRight, .bottom]
        case "6":
            return [.top, .upperLeft, .middle, .lowerLeft, .lowerRight, .bottom]
        case "7":
            return [.top, .upperRight, .lowerRight]
        case "8":
            return [.top, .upperLeft, .upperRight, .middle, .lowerLeft, .lowerRight, .bottom]
        case "9":
            return [.top, .upperLeft, .upperRight, .middle, .lowerRight, .bottom]
        case "-":
            return [.middle]
        default:
            return []
        }
    }
}

private struct Segment: View {
    let isActive: Bool

    var body: some View {
        Capsule()
            .fill(isActive ? Color.primary : Color.clear)
    }
}

private enum SevenSegment {
    case top
    case upperLeft
    case upperRight
    case middle
    case lowerLeft
    case lowerRight
    case bottom
}

private extension NSImage {
    static func casioSkin(named fileName: String) -> NSImage? {
        let fileExtension = "png"
        let bundleName = "ChatGPTQuotaMenu_ChatGPTQuotaMenu.bundle"
        let executableDirectory = Bundle.main.bundleURL.deletingLastPathComponent()

        let candidateURLs: [URL?] = [
            Bundle.main.url(forResource: fileName, withExtension: fileExtension),
            Bundle.module.url(forResource: fileName, withExtension: fileExtension),
            Bundle.main.bundleURL
                .appendingPathComponent(bundleName)
                .appendingPathComponent("\(fileName).\(fileExtension)"),
            Bundle.main.resourceURL?
                .appendingPathComponent(bundleName)
                .appendingPathComponent("\(fileName).\(fileExtension)"),
            executableDirectory
                .appendingPathComponent(bundleName)
                .appendingPathComponent("\(fileName).\(fileExtension)")
        ]

        for candidateURL in candidateURLs {
            guard let candidateURL else {
                continue
            }
            if let image = NSImage(contentsOf: candidateURL) {
                return image
            }
        }

        return nil
    }
}

private extension View {
    func frame(in rect: CGRect) -> some View {
        frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
    }
}

private extension Color {
    init(hex: UInt, opacity: Double = 1) {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }
}
