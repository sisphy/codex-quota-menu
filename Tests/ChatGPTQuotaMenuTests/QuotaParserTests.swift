import Foundation
import XCTest
@testable import ChatGPTQuotaMenu

final class QuotaParserTests: XCTestCase {
    func testParsesEnglishShortWindowQuota() throws {
        let now = try XCTUnwrap(DateComponents(calendar: .current, year: 2026, month: 5, day: 20, hour: 12).date)
        let text = """
        GPT-5.5
        123 / 160 messages remaining
        Resets in 1h 30m
        """

        let snapshots = QuotaParser().parse(text, now: now)
        let short = try XCTUnwrap(snapshots.first(where: { $0.window == .shortWindow }))

        XCTAssertEqual(short.remaining, 123)
        XCTAssertEqual(short.limit, 160)
        XCTAssertEqual(short.modelName, "GPT-5.5")
        XCTAssertEqual(short.resetAt, Calendar.current.date(byAdding: .minute, value: 90, to: now))
    }

    func testParsesEnglishWeeklyThinkingQuota() throws {
        let text = """
        GPT-5.5 Thinking
        2860 of 3000 messages remaining this week
        Resets in 4h
        """

        let snapshots = QuotaParser().parse(text)
        let weekly = try XCTUnwrap(snapshots.first(where: { $0.window == .weeklyThinking }))

        XCTAssertEqual(weekly.remaining, 2860)
        XCTAssertEqual(weekly.limit, 3000)
        XCTAssertEqual(weekly.modelName, "GPT-5.5 Thinking")
    }

    func testParsesChineseQuotaText() throws {
        let now = try XCTUnwrap(DateComponents(calendar: .current, year: 2026, month: 5, day: 20, hour: 12).date)
        let text = """
        GPT-5.5 思考
        本周剩余 2990 / 3000 条消息
        2 小时 15 分后重置
        """

        let snapshots = QuotaParser().parse(text, now: now)
        let weekly = try XCTUnwrap(snapshots.first(where: { $0.window == .weeklyThinking }))

        XCTAssertEqual(weekly.remaining, 2990)
        XCTAssertEqual(weekly.limit, 3000)
        XCTAssertEqual(weekly.resetAt, Calendar.current.date(byAdding: .minute, value: 135, to: now))
    }

    func testIgnoresUnrelatedText() {
        let snapshots = QuotaParser().parse("New chat\nExplore GPTs\nSettings")
        XCTAssertTrue(snapshots.isEmpty)
    }

    func testParsesUntilStyleQuotaText() throws {
        let now = try XCTUnwrap(DateComponents(calendar: .current, year: 2026, month: 5, day: 20, hour: 12).date)
        let text = """
        GPT-5.5
        You have 123 messages until 4:30 PM
        """

        let snapshots = QuotaParser().parse(text, now: now)
        let short = try XCTUnwrap(snapshots.first(where: { $0.window == .shortWindow }))

        XCTAssertEqual(short.remaining, 123)
        XCTAssertEqual(short.resetAt, Calendar.current.date(from: DateComponents(year: 2026, month: 5, day: 20, hour: 16, minute: 30)))
    }
}
