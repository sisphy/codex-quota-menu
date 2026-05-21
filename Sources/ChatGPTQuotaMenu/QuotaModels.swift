import Foundation

enum QuotaWindow: String, Codable, CaseIterable, Sendable {
    case shortWindow
    case weeklyThinking

    var displayName: String {
        switch self {
        case .shortWindow:
            return "5小时额度"
        case .weeklyThinking:
            return "一周额度"
        }
    }
}

enum QuotaDialStyle: String, CaseIterable, Identifiable, Sendable {
    case glass
    case casio
    case eink

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .glass:
            return "玻璃卡片"
        case .casio:
            return "电子表"
        case .eink:
            return "电子墨水"
        }
    }
}

struct QuotaSnapshot: Codable, Identifiable, Equatable, Sendable {
    var id: String { window.rawValue }

    let modelName: String
    let window: QuotaWindow
    let remaining: Int?
    let limit: Int?
    let resetAt: Date?
    let rawText: String
    let confidence: Double
    let capturedAt: Date

    var displayAmount: String {
        switch (remaining, limit) {
        case let (.some(remaining), .some(limit)):
            if limit == 100 {
                return "\(remaining)%"
            }
            return "\(remaining)/\(limit)"
        case let (.some(remaining), .none):
            return "\(remaining) left"
        case let (.none, .some(limit)):
            return "limit \(limit)"
        default:
            return "未知"
        }
    }
}

enum QuotaReadState: Equatable, Sendable {
    case loggedOut
    case loading
    case ready([QuotaSnapshot])
    case stale([QuotaSnapshot], reason: String)
    case unreadable(reason: String)
}

extension QuotaReadState {
    var snapshots: [QuotaSnapshot] {
        switch self {
        case .ready(let snapshots), .stale(let snapshots, _):
            return snapshots
        case .loggedOut, .loading, .unreadable:
            return []
        }
    }
}
