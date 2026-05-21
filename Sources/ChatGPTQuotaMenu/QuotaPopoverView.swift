import SwiftUI

struct QuotaPopoverView: View {
    @ObservedObject var viewModel: QuotaViewModel
    let isFloatingVisible: Bool
    let toggleFloating: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            controls
        }
        .padding(.vertical, 10)
        .frame(width: 232, height: 292, alignment: .topLeading)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "gauge.with.dots.needle.67percent")
                .font(.system(size: 20, weight: .medium))
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text("ChatGPT 额度")
                    .font(.system(size: 14, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if viewModel.isRefreshing {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loggedOut:
            EmptyStateView(
                icon: "person.crop.circle.badge.exclamationmark",
                title: "需要登录",
                message: "请先在 Codex 客户端或 CLI 登录 ChatGPT。"
            )
        case .loading:
            EmptyStateView(
                icon: "arrow.triangle.2.circlepath",
                title: "正在读取",
                message: "正在读取 Codex 本地 rate limit 接口。"
            )
        case .unreadable(let reason):
            EmptyStateView(
                icon: "exclamationmark.magnifyingglass",
                title: "无法读取",
                message: reason
            )
        case .ready(let snapshots):
            snapshotsView(snapshots: snapshots, staleReason: nil)
        case .stale(let snapshots, let reason):
            snapshotsView(snapshots: snapshots, staleReason: reason)
        }
    }

    private var subtitle: String {
        switch viewModel.state {
        case .ready(let snapshots):
            return "最后读取 \(lastCapturedText(snapshots))"
        case .stale(let snapshots, _):
            return "上次读取 \(lastCapturedText(snapshots))"
        case .loggedOut:
            return "未登录"
        case .loading:
            return "读取中"
        case .unreadable:
            return "暂无可用快照"
        }
    }

    private func snapshotsView(snapshots: [QuotaSnapshot], staleReason: String?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(QuotaWindow.allCases, id: \.self) { window in
                QuotaCard(snapshot: snapshots.first(where: { $0.window == window }), window: window)
            }

            if let staleReason {
                Text(staleReason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 2) {
            MenuActionRow(
                icon: isFloatingVisible ? "eye.slash" : "eye",
                title: isFloatingVisible ? "隐藏悬浮框" : "显示悬浮框"
            ) {
                toggleFloating()
            }
            DialStyleMenu(
                selectedStyle: viewModel.dialStyle,
                isDisabled: isFloatingVisible == false,
                selectStyle: viewModel.setDialStyle
            )
            MenuActionRow(icon: "arrow.clockwise", title: "刷新", isDisabled: viewModel.isRefreshing) {
                Task { await viewModel.refresh() }
            }
            MenuActionRow(icon: "stethoscope", title: "诊断") {
                viewModel.openDiagnosticText()
            }
            MenuActionRow(icon: "power", title: "退出") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.horizontal, 8)
    }

    private func lastCapturedText(_ snapshots: [QuotaSnapshot]) -> String {
        guard let date = snapshots.map(\.capturedAt).max() else {
            return "未知"
        }
        return date.formatted(date: .omitted, time: .shortened)
    }
}

private struct DialStyleMenu: View {
    let selectedStyle: QuotaDialStyle
    var isDisabled = false
    let selectStyle: (QuotaDialStyle) -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "dial.medium")
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 22)
                    .foregroundStyle(isDisabled ? .tertiary : .secondary)
                Text("表盘风格")
                    .font(.system(size: 14, weight: .regular))
                Spacer()
                Text(selectedStyle.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isDisabled ? .tertiary : .secondary)
            }
            .foregroundStyle(isDisabled ? .tertiary : .primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 34)
            .padding(.horizontal, 8)
            .background(isHovered && isDisabled == false ? Color.primary.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 7))

            Picker("", selection: styleBinding) {
                ForEach(QuotaDialStyle.allCases) { style in
                    Text(style.displayName)
                        .tag(style)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .disabled(isDisabled)
            .opacity(isDisabled ? 0.45 : 1)
            .padding(.horizontal, 8)
        }
        .onHover { isHovered = $0 }
    }

    private var styleBinding: Binding<QuotaDialStyle> {
        Binding(
            get: { selectedStyle },
            set: { selectStyle($0) }
        )
    }
}

private struct MenuActionRow: View {
    let icon: String
    let title: String
    var isDisabled = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 22)
                    .foregroundStyle(isDisabled ? .tertiary : .secondary)
                Text(title)
                    .font(.system(size: 14))
                Spacer()
            }
            .foregroundStyle(isDisabled ? .tertiary : .primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 34)
            .padding(.horizontal, 8)
            .background(isHovered && isDisabled == false ? Color.primary.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .onHover { isHovered = $0 }
    }
}

private struct QuotaCard: View {
    let snapshot: QuotaSnapshot?
    let window: QuotaWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(window.displayName)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(snapshot?.modelName ?? "未读取")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .lastTextBaseline) {
                Text(snapshot?.displayAmount ?? "未知")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(resetText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(confidenceText)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
    }

    private var resetText: String {
        guard let resetAt = snapshot?.resetAt else {
            return "重置时间未知"
        }
        let resetText = window == .weeklyThinking
            ? resetAt.formatted(.dateTime.month(.abbreviated).day().hour().minute())
            : resetAt.formatted(date: .omitted, time: .shortened)
        return "重置 \(resetText)"
    }

    private var confidenceText: String {
        guard let confidence = snapshot?.confidence else {
            return "置信度 0%"
        }
        return "置信度 \(Int(confidence * 100))%"
    }
}

private struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }
}
