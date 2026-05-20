import Foundation

actor QuotaStore {
    private let fileURL: URL
    nonisolated let rawTextURL: URL

    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("ChatGPTQuotaMenu", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.fileURL = directory.appendingPathComponent("snapshots.json")
        self.rawTextURL = directory.appendingPathComponent("last-page-text.txt")
    }

    func load() -> [QuotaSnapshot] {
        guard let data = try? Data(contentsOf: fileURL) else {
            return []
        }
        return (try? JSONDecoder.quota.decode([QuotaSnapshot].self, from: data)) ?? []
    }

    func save(_ snapshots: [QuotaSnapshot]) {
        guard let data = try? JSONEncoder.quota.encode(snapshots) else {
            return
        }
        try? data.write(to: fileURL, options: .atomic)
    }

    func saveRawText(_ text: String) {
        let header = """
        Captured at: \(Date().ISO8601Format())
        This file contains visible text and accessibility labels read from the embedded ChatGPT page.

        """
        try? (header + text).write(to: rawTextURL, atomically: true, encoding: .utf8)
    }
}

private extension JSONEncoder {
    static var quota: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var quota: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
