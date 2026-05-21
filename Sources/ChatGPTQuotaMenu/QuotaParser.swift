import Foundation

struct QuotaParser: Sendable {
    func parse(_ text: String, now: Date = Date(), calendar: Calendar = .current) -> [QuotaSnapshot] {
        let normalized = normalize(text)
        guard normalized.isEmpty == false else {
            return []
        }

        let chunks = makeChunks(from: normalized)
        let candidates = chunks.compactMap { parseChunk($0, now: now, calendar: calendar) }

        var bestByWindow: [QuotaWindow: QuotaSnapshot] = [:]
        for candidate in candidates {
            let existing = bestByWindow[candidate.window]
            if existing == nil || candidate.confidence > existing!.confidence {
                bestByWindow[candidate.window] = candidate
            }
        }

        return QuotaWindow.allCases.compactMap { bestByWindow[$0] }
    }

    private func parseChunk(_ chunk: String, now: Date, calendar: Calendar) -> QuotaSnapshot? {
        guard let window = inferWindow(from: chunk) else {
            return nil
        }

        let amount = parseAmount(from: chunk)
        let resetAt = parseReset(from: chunk, now: now, calendar: calendar)
        let modelName = parseModelName(from: chunk, window: window)
        let confidence = score(window: window, chunk: chunk, amount: amount, resetAt: resetAt)

        guard confidence >= 0.35 else {
            return nil
        }

        return QuotaSnapshot(
            modelName: modelName,
            window: window,
            remaining: amount.remaining,
            limit: amount.limit,
            resetAt: resetAt,
            rawText: String(chunk.prefix(500)),
            confidence: confidence,
            capturedAt: now
        )
    }

    private func normalize(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
            .joined(separator: "\n")
    }

    private func makeChunks(from text: String) -> [String] {
        let lines = text.split(separator: "\n").map(String.init)
        var chunks: [String] = []

        for index in lines.indices {
            let line = lines[index]
            guard isQuotaRelevant(line) else {
                continue
            }

            let start = max(lines.startIndex, index - 3)
            let end = min(lines.endIndex, index + 4)
            chunks.append(lines[start..<end].joined(separator: "\n"))
        }

        if chunks.isEmpty, isQuotaRelevant(text) {
            chunks.append(text)
        }

        return chunks
    }

    private func isQuotaRelevant(_ text: String) -> Bool {
        let lower = text.lowercased()
        let markers = [
            "gpt", "thinking", "reasoning", "remaining", "left", "limit", "reset", "resets",
            "message", "messages", "weekly", "week", "until", "available",
            "剩余", "额度", "限制", "重置", "本周", "每周", "消息", "条", "思考", "可用", "可使用"
        ]
        return markers.contains { lower.contains($0) }
    }

    private func inferWindow(from text: String) -> QuotaWindow? {
        let lower = text.lowercased()

        if lower.contains("thinking") ||
            lower.contains("reasoning") ||
            lower.contains("weekly") ||
            lower.contains("per week") ||
            lower.contains("week") ||
            lower.contains("本周") ||
            lower.contains("每周") ||
            lower.contains("思考") {
            return .weeklyThinking
        }

        if lower.contains("gpt") ||
            lower.contains("message") ||
            lower.contains("messages") ||
            lower.contains("hour") ||
            lower.contains("until") ||
            lower.contains("小时") ||
            lower.contains("短") ||
            lower.contains("额度") {
            return .shortWindow
        }

        return nil
    }

    private func parseModelName(from text: String, window: QuotaWindow) -> String {
        let lower = text.lowercased()
        if lower.contains("gpt-5.5") || lower.contains("gpt 5.5") {
            return window == .weeklyThinking ? "GPT-5.5 Thinking" : "GPT-5.5"
        }
        if lower.contains("gpt-5") || lower.contains("gpt 5") {
            return window == .weeklyThinking ? "GPT-5 Thinking" : "GPT-5"
        }
        return window == .weeklyThinking ? "Thinking" : "ChatGPT"
    }

    private func parseAmount(from text: String) -> (remaining: Int?, limit: Int?) {
        if let pair = firstMatch(#"(?i)(\d{1,5})\s*(?:/|of|out of|共|\/)\s*(\d{1,5})"#, in: text) {
            return (Int(pair[1]), Int(pair[2]))
        }

        if let remaining = firstMatch(#"(?i)(\d{1,5})\s*(?:messages?|条)?\s*(?:remaining|left|剩余|可用)"#, in: text) {
            return (Int(remaining[1]), nil)
        }

        if let remaining = firstMatch(#"(?i)(?:remaining|left|剩余|可用)\D{0,12}(\d{1,5})"#, in: text) {
            return (Int(remaining[1]), nil)
        }

        if let remaining = firstMatch(#"(?i)(?:you have|available|可使用|还可使用|剩余可使用)\D{0,12}(\d{1,5})\s*(?:messages?|条|次)?"#, in: text) {
            return (Int(remaining[1]), nil)
        }

        if let remaining = firstMatch(#"(?i)(\d{1,5})\s*(?:messages?|条|次)\s*(?:until|available|可用|可使用)"#, in: text) {
            return (Int(remaining[1]), nil)
        }

        if let limit = firstMatch(#"(?i)(?:limit|最多|上限|限制)\D{0,12}(\d{1,5})"#, in: text) {
            return (nil, Int(limit[1]))
        }

        return (nil, nil)
    }

    private func parseReset(from text: String, now: Date, calendar: Calendar) -> Date? {
        if let match = firstMatch(#"(?i)resets?\s+in\s+(\d{1,3})\s*h(?:ours?)?\s*(?:(\d{1,2})\s*m(?:in(?:ute)?s?)?)?"#, in: text) {
            let hours = Int(match[1]) ?? 0
            let minutes = match.count > 2 ? Int(match[2]) ?? 0 : 0
            return calendar.date(byAdding: .minute, value: hours * 60 + minutes, to: now)
        }

        if let match = firstMatch(#"(?i)resets?\s+in\s+(\d{1,3})\s*(?:m|min|minutes?)"#, in: text) {
            return calendar.date(byAdding: .minute, value: Int(match[1]) ?? 0, to: now)
        }

        if let match = firstMatch(#"(?i)(?:resets?|reset|until|after)\D{0,12}(\d{1,2})(?::(\d{2}))?\s*(am|pm)?"#, in: text) {
            return dateTodayOrTomorrow(hourText: match[1], minuteText: match.count > 2 ? match[2] : "", meridiem: match.count > 3 ? match[3] : "", now: now, calendar: calendar)
        }

        if let match = firstMatch(#"(?i)(?:重置|恢复)\D{0,8}(\d{1,3})\s*小时\s*(?:(\d{1,2})\s*分)?"#, in: text) {
            let hours = Int(match[1]) ?? 0
            let minutes = match.count > 2 ? Int(match[2]) ?? 0 : 0
            return calendar.date(byAdding: .minute, value: hours * 60 + minutes, to: now)
        }

        if let match = firstMatch(#"(?i)(\d{1,3})\s*小时\s*(?:(\d{1,2})\s*分)?\D{0,8}(?:重置|恢复)"#, in: text) {
            let hours = Int(match[1]) ?? 0
            let minutes = match.count > 2 ? Int(match[2]) ?? 0 : 0
            return calendar.date(byAdding: .minute, value: hours * 60 + minutes, to: now)
        }

        if let match = firstMatch(#"(?i)(?:重置|恢复)\D{0,8}(\d{1,3})\s*分"#, in: text) {
            return calendar.date(byAdding: .minute, value: Int(match[1]) ?? 0, to: now)
        }

        if let match = firstMatch(#"(?i)(\d{1,3})\s*分\D{0,8}(?:重置|恢复)"#, in: text) {
            return calendar.date(byAdding: .minute, value: Int(match[1]) ?? 0, to: now)
        }

        if let match = firstMatch(#"(?i)(?:重置|恢复|直到|于)\D{0,8}(\d{1,2})(?::|：)(\d{2})"#, in: text) {
            return dateTodayOrTomorrow(hourText: match[1], minuteText: match[2], meridiem: "", now: now, calendar: calendar)
        }

        return nil
    }

    private func dateTodayOrTomorrow(
        hourText: String,
        minuteText: String,
        meridiem: String,
        now: Date,
        calendar: Calendar
    ) -> Date? {
        guard var hour = Int(hourText) else {
            return nil
        }
        let minute = Int(minuteText) ?? 0
        let lowerMeridiem = meridiem.lowercased()
        if lowerMeridiem == "pm", hour < 12 {
            hour += 12
        } else if lowerMeridiem == "am", hour == 12 {
            hour = 0
        }

        guard hour >= 0, hour <= 23, minute >= 0, minute <= 59 else {
            return nil
        }

        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = hour
        components.minute = minute
        components.second = 0

        guard let today = calendar.date(from: components) else {
            return nil
        }

        if today > now {
            return today
        }
        return calendar.date(byAdding: .day, value: 1, to: today)
    }

    private func score(
        window: QuotaWindow,
        chunk: String,
        amount: (remaining: Int?, limit: Int?),
        resetAt: Date?
    ) -> Double {
        let lower = chunk.lowercased()
        var score = 0.2

        if amount.remaining != nil { score += 0.25 }
        if amount.limit != nil { score += 0.2 }
        if resetAt != nil { score += 0.2 }
        if lower.contains("gpt") { score += 0.08 }
        if lower.contains("reset") || lower.contains("重置") { score += 0.08 }

        switch window {
        case .weeklyThinking:
            if lower.contains("thinking") || lower.contains("思考") { score += 0.12 }
            if lower.contains("week") || lower.contains("周") { score += 0.12 }
        case .shortWindow:
            if lower.contains("hour") || lower.contains("小时") { score += 0.12 }
            if lower.contains("message") || lower.contains("消息") || lower.contains("条") { score += 0.08 }
        }

        return min(score, 1)
    }

    private func firstMatch(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range) else {
            return nil
        }

        return (0..<match.numberOfRanges).map { index in
            let nsRange = match.range(at: index)
            guard let range = Range(nsRange, in: text) else {
                return ""
            }
            return String(text[range])
        }
    }
}
