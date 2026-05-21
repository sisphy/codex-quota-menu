import Foundation

struct CodexRateLimitReader: Sendable {
    let store: QuotaStore

    func refresh() async -> Result<[QuotaSnapshot], QuotaReaderError> {
        await Task.detached {
            do {
                let response = try runAppServerProbe()
                await store.saveRawText(response)
                let snapshots = try parseSnapshots(from: response)
                return snapshots.isEmpty
                    ? .failure(.unreadable("Codex rateLimits 接口返回了空结果。"))
                    : .success(snapshots)
            } catch let error as QuotaReaderError {
                return .failure(error)
            } catch {
                return .failure(.scriptFailed(error.localizedDescription))
            }
        }.value
    }

    private func runAppServerProbe() throws -> String {
        let process = Process()
        process.executableURL = try codexExecutableURL()
        process.arguments = ["app-server", "--listen", "stdio://"]

        let input = Pipe()
        let output = Pipe()
        let error = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = error

        try process.run()

        let messages = [
            #"{"method":"initialize","id":1,"params":{"clientInfo":{"name":"chatgpt_quota_menu","title":"ChatGPT Quota Menu","version":"0.1.0"}}}"#,
            #"{"method":"initialized","params":{}}"#,
            #"{"method":"account/read","id":2,"params":{"refreshToken":true}}"#,
            #"{"method":"account/rateLimits/read","id":3}"#
        ].joined(separator: "\n") + "\n"

        input.fileHandleForWriting.write(Data(messages.utf8))

        let deadline = Date().addingTimeInterval(18)
        var buffer = Data()
        while Date() < deadline {
            let chunk = output.fileHandleForReading.availableData
            if chunk.isEmpty == false {
                buffer.append(chunk)
                if String(data: buffer, encoding: .utf8)?.contains(#""id":3"#) == true {
                    process.terminate()
                    return String(data: buffer, encoding: .utf8) ?? ""
                }
            }
            Thread.sleep(forTimeInterval: 0.05)
        }

        process.terminate()
        let stderr = String(data: error.fileHandleForReading.availableData, encoding: .utf8) ?? ""
        throw QuotaReaderError.scriptFailed(stderr.isEmpty ? "Codex app-server 没有返回额度结果。" : stderr)
    }

    private func parseSnapshots(from output: String) throws -> [QuotaSnapshot] {
        let lines = output
            .split(separator: "\n")
            .map(String.init)
            .filter { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }

        var rateLimits: [String: Any]?
        for line in lines {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  (object["id"] as? Int) == 3,
                  let result = object["result"] as? [String: Any],
                  let limits = result["rateLimits"] as? [String: Any] else {
                continue
            }
            rateLimits = limits
            break
        }

        guard let rateLimits else {
            throw QuotaReaderError.unreadable("没有在 Codex app-server 响应里找到 rateLimits。")
        }

        let now = Date()
        let rawText = compactJSON(rateLimits)
        return [
            snapshot(window: .shortWindow, value: rateLimits["primary"], now: now, rawText: rawText),
            snapshot(window: .weeklyThinking, value: rateLimits["secondary"], now: now, rawText: rawText)
        ].compactMap { $0 }
    }

    private func snapshot(window: QuotaWindow, value: Any?, now: Date, rawText: String) -> QuotaSnapshot? {
        guard let object = value as? [String: Any] else {
            return nil
        }

        let usedPercent = number(object["usedPercent"])
        let remaining = usedPercent.map { max(0, min(100, 100 - Int($0.rounded()))) }
        let resetAt = number(object["resetsAt"]).map { Date(timeIntervalSince1970: $0) }

        return QuotaSnapshot(
            modelName: window.displayName,
            window: window,
            remaining: remaining,
            limit: 100,
            resetAt: resetAt,
            rawText: rawText,
            confidence: usedPercent == nil ? 0.6 : 1,
            capturedAt: now
        )
    }

    private func number(_ value: Any?) -> Double? {
        if let value = value as? Double {
            return value
        }
        if let value = value as? Int {
            return Double(value)
        }
        if let value = value as? String {
            return Double(value)
        }
        return nil
    }

    private func compactJSON(_ object: Any) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8) else {
            return "\(object)"
        }
        return string
    }

    private func codexExecutableURL() throws -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent(".local/bin/codex"),
            URL(fileURLWithPath: "/opt/homebrew/bin/codex"),
            URL(fileURLWithPath: "/usr/local/bin/codex"),
            URL(fileURLWithPath: "/usr/bin/codex")
        ]

        if let candidate = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) {
            return candidate
        }

        throw QuotaReaderError.scriptFailed("找不到 codex 可执行文件。")
    }
}
