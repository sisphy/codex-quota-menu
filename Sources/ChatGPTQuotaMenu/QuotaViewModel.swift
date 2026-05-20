import Foundation
import AppKit

@MainActor
final class QuotaViewModel: ObservableObject {
    @Published private(set) var state: QuotaReadState = .loading
    @Published private(set) var isRefreshing = false

    private let store = QuotaStore()
    private lazy var reader = CodexRateLimitReader(store: store)
    private var refreshTask: Task<Void, Never>?
    private var timerTask: Task<Void, Never>?

    init() {
        refreshTask = Task { [weak self] in
            guard let self else { return }
            let cached = await store.load()
            if cached.isEmpty == false {
                state = .stale(cached, reason: "显示上次成功读取结果")
            }
            await refresh()
            startTimer()
        }
    }

    deinit {
        refreshTask?.cancel()
        timerTask?.cancel()
    }

    var statusTitle: String {
        switch state {
        case .loggedOut:
            return "Codex 登录"
        case .loading:
            return "读取中"
        case .unreadable:
            return "无法读取"
        case .ready(let snapshots), .stale(let snapshots, _):
            if let short = snapshots.first(where: { $0.window == .shortWindow }) {
                if let remaining = short.remaining {
                    return "Codex \(remaining)%"
                }
                return "Codex"
            }
            return "Codex 额度"
        }
    }

    func refresh() async {
        guard isRefreshing == false else {
            return
        }
        isRefreshing = true
        state = state.snapshots.isEmpty ? .loading : .stale(state.snapshots, reason: "正在刷新")
        let result = await reader.refresh()
        isRefreshing = false

        switch result {
        case .success(let snapshots):
            await store.save(snapshots)
            state = .ready(snapshots)
        case .failure(.loggedOut):
            state = .loggedOut
        case .failure(.unreadable(let reason)):
            let cached = await store.load()
            state = cached.isEmpty ? .unreadable(reason: reason) : .stale(cached, reason: reason)
        case .failure(.navigationFailed(let reason)), .failure(.scriptFailed(let reason)):
            let cached = await store.load()
            let message = reason.isEmpty ? "读取失败" : reason
            state = cached.isEmpty ? .unreadable(reason: message) : .stale(cached, reason: message)
        }
    }

    func openLoginWindow() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Codex.app"))
    }

    func openDiagnosticText() {
        NSWorkspace.shared.open(store.rawTextURL)
    }

    private func startTimer() {
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            while Task.isCancelled == false {
                try? await Task.sleep(for: .seconds(60))
                await self?.refresh()
            }
        }
    }

    static func relative(_ date: Date, now: Date = Date()) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(now)))
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}
