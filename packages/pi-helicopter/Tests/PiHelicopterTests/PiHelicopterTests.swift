import AppKit
import XCTest
@testable import PiHelicopter

final class PiHelicopterTests: XCTestCase {
    func testParserReadsUsageToolsAndLanguages() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let file = directory.appendingPathComponent("session.jsonl")
        let records = [
            #"{"type":"session","id":"abc","cwd":"/Users/test/Repos/pilot"}"#,
            #"{"type":"message","timestamp":"2026-03-10T10:00:00.000Z","message":{"role":"user"}}"#,
            #"{"type":"message","timestamp":"2026-03-10T10:00:01.000Z","message":{"role":"assistant","model":"claude-test","usage":{"input":10,"output":20,"cacheRead":30,"cacheWrite":40,"cost":{"total":0.25}},"content":[{"type":"toolCall","name":"edit","arguments":{"path":"main.swift","newText":"one\ntwo"}}]}}"#,
            #"{"type":"message","timestamp":"2026-03-10T10:00:02.000Z","message":{"role":"toolResult"}}"#
        ]
        try records.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)

        let stats = try SessionParser.parse(fileAt: file, size: 1, modifiedAt: 2)
        let day = try XCTUnwrap(stats.days["2026-03-10"])

        XCTAssertEqual(stats.sessionID, "abc")
        XCTAssertEqual(stats.project, "pilot")
        XCTAssertEqual(day.cost, 0.25, accuracy: 0.0001)
        XCTAssertEqual(day.tokens, TokenCounts(input: 10, output: 20, cacheRead: 30, cacheWrite: 40))
        XCTAssertEqual(day.userMessages, 1)
        XCTAssertEqual(day.assistantMessages, 1)
        XCTAssertEqual(day.toolResults, 1)
        XCTAssertEqual(day.modelMessages["claude-test"], 1)
        XCTAssertEqual(day.tools["edit"], 1)
        XCTAssertEqual(day.languageLines["Swift"], 2)
    }

    @MainActor
    func testSummaryFiltersAndCombinesSessions() {
        let calendar = Calendar.current
        let today = Dates.day.string(from: Date())
        let oldDate = calendar.date(byAdding: .day, value: -10, to: Date())!
        let old = Dates.day.string(from: oldDate)
        let sessions = [
            "one": SessionStats(
                path: "/tmp/one.jsonl",
                size: 1,
                modifiedAt: 1,
                sessionID: "one",
                project: "alpha",
                startedAt: Date().timeIntervalSince1970 - 60,
                endedAt: Date().timeIntervalSince1970,
                days: [today: DayStats(cost: 1, tokens: TokenCounts(input: 10), assistantMessages: 1)]
            ),
            "two": SessionStats(
                path: "/tmp/two.jsonl",
                size: 1,
                modifiedAt: 1,
                sessionID: "two",
                project: "beta",
                days: [old: DayStats(cost: 2, tokens: TokenCounts(output: 20), assistantMessages: 1)]
            )
        ]
        let store = StatsStore(sessionsURL: URL(fileURLWithPath: "/tmp/none"), sessions: sessions)

        let day = store.summary(for: .day)
        XCTAssertEqual(day.cost, 1)
        XCTAssertEqual(day.sessionCount, 1)
        XCTAssertEqual(day.tokens.total, 10)

        let month = store.summary(for: .month)
        XCTAssertEqual(month.cost, 3)
        XCTAssertEqual(month.sessionCount, 2)
        XCTAssertEqual(month.tokens.total, 30)
    }

    @MainActor
    func testVisualizationsDrawInMacAppearances() throws {
        let spend = DailySpendChartView(
            data: [(day: "2026-08-22", cost: 12.5), (day: "2026-08-23", cost: 4.25)],
            range: .week
        )
        let summary = Summary(
            cost: 16.75,
            tokens: TokenCounts(input: 10, output: 20),
            userMessages: 2,
            assistantMessages: 3,
            sessionCount: 4,
            daysActive: 2,
            models: [NamedValue(name: "test-model", primary: 12, count: 8)],
            projects: [NamedValue(name: "test-project", primary: 10, count: 2)],
            languages: [NamedValue(name: "Swift", primary: 80, count: 4)],
            tools: [NamedValue(name: "read", primary: 5, count: 5)]
        )
        let today = Summary(cost: 2.5)
        let overview = OverviewView(summary: summary, today: today)
        let bars = BarListView(tab: .models, summary: summary)
        let rangePicker = RangePickerView(selected: .week) { _ in }
        let tabPicker = TabPickerView(selected: .models) { _ in }
        let rangeControl = try XCTUnwrap(rangePicker.subviews.first as? NSSegmentedControl)
        let tabControl = try XCTUnwrap(tabPicker.subviews.first as? NSSegmentedControl)
        XCTAssertEqual(rangePicker.frame.height, tabPicker.frame.height)
        XCTAssertEqual(rangeControl.controlSize, tabControl.controlSize)
        XCTAssertEqual(rangeControl.intrinsicContentSize.height, tabControl.intrinsicContentSize.height)
        XCTAssertEqual(tabControl.segmentCount, 5)
        for tab in DashboardTab.allCases {
            XCTAssertNotNil(NSImage(
                systemSymbolName: tab.symbolName,
                accessibilityDescription: tab.title
            ))
        }
        XCTAssertEqual((0..<tabControl.segmentCount).reduce(0) {
            $0 + tabControl.width(forSegment: $1)
        }, MenuStyle.contentWidth)

        let appearances: [NSAppearance.Name] = [
            .aqua,
            .darkAqua,
            .accessibilityHighContrastAqua,
            .accessibilityHighContrastDarkAqua
        ]

        for appearanceName in appearances {
            let appearance = try XCTUnwrap(NSAppearance(named: appearanceName))
            for view in [spend, overview] {
                view.appearance = appearance
                let image = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
                view.cacheDisplay(in: view.bounds, to: image)
                XCTAssertGreaterThan(image.pixelsWide, 0)
            }
            bars.appearance = appearance
            for tab in DashboardTab.allCases {
                bars.update(tab: tab, summary: summary)
                let image = try XCTUnwrap(bars.bitmapImageRepForCachingDisplay(in: bars.bounds))
                bars.cacheDisplay(in: bars.bounds, to: image)
                XCTAssertGreaterThan(image.pixelsWide, 0)
            }
        }

        bars.update(tab: .tokens, summary: summary)
        let tokenAccessibility = try XCTUnwrap(bars.accessibilityValue() as? String)
        XCTAssertTrue(tokenAccessibility.contains("Total"))
        XCTAssertTrue(tokenAccessibility.contains("Cached"))
        XCTAssertTrue(tokenAccessibility.contains("Input"))
        XCTAssertTrue(tokenAccessibility.contains("Output"))
        XCTAssertEqual(DateRange.day.shortTitle, "Today")
        XCTAssertEqual(DateRange.quarter.days, 90)
    }

    func testFormatsSupportedCurrencies() {
        XCTAssertEqual(MoneyFormat.usd.money(12.5), "$12.50")
        XCTAssertEqual(MoneyFormat(currency: .eur, usdRate: 0.8).money(10), "€8.00")
        XCTAssertEqual(MoneyFormat(currency: .eur, usdRate: 0.8).chartMoney(0), "€0")
        XCTAssertEqual(MoneyFormat(currency: .jpy, usdRate: 150).money(10), "¥1500")
        XCTAssertEqual(MoneyFormat(currency: .gbp, usdRate: 0.7).money(10), "£7.00")
        XCTAssertEqual(MoneyFormat(currency: .cny, usdRate: 7).money(10), "CN¥70.00")
    }

    func testParsesECBCurrencyRates() throws {
        let xml = Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <Envelope><Cube><Cube time="2026-08-21">
        <Cube currency="USD" rate="1.2"/>
        <Cube currency="JPY" rate="180"/>
        <Cube currency="GBP" rate="0.84"/>
        <Cube currency="CNY" rate="7.2"/>
        </Cube></Cube></Envelope>
        """.utf8)
        let fetchedAt = Date(timeIntervalSince1970: 100)
        let rates = try CurrencyRates.parseECB(data: xml, fetchedAt: fetchedAt)

        XCTAssertEqual(rates.fetchedAt, fetchedAt)
        XCTAssertEqual(rates.usdRates["USD"], 1)
        XCTAssertEqual(try XCTUnwrap(rates.usdRates["EUR"]), 1 / 1.2, accuracy: 0.0001)
        XCTAssertEqual(rates.usdRates["JPY"], 150)
        XCTAssertEqual(rates.usdRates["GBP"], 0.7)
        XCTAssertEqual(rates.usdRates["CNY"], 6)
    }

    func testFindsLatestPiHelicopterRelease() throws {
        let data = Data("""
        [
          {"tag_name":"another-tool-v9.0.0","draft":false,"prerelease":false},
          {"tag_name":"pi-helicopter-v0.3.0","draft":true,"prerelease":false},
          {"tag_name":"pi-helicopter-v0.2.1","draft":false,"prerelease":true},
          {"tag_name":"pi-helicopter-v0.1.9","draft":false,"prerelease":false},
          {"tag_name":"pi-helicopter-v0.2.0","draft":false,"prerelease":false}
        ]
        """.utf8)

        XCTAssertEqual(try AppUpdate.latestVersion(data: data), AppVersion(value: "0.2.0"))
        let older = try XCTUnwrap(AppVersion(value: "0.9.9"))
        let newer = try XCTUnwrap(AppVersion(value: "0.10.0"))
        XCTAssertLessThan(older, newer)
        XCTAssertNil(AppVersion(value: "0.1"))
    }

    func testScannerReusesAndUpdatesCache() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let sessions = directory.appendingPathComponent("sessions", isDirectory: true)
        let cache = directory.appendingPathComponent("cache.plist")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let file = sessions.appendingPathComponent("one.jsonl")
        try #"{"type":"session","id":"one","cwd":"/tmp/alpha"}"#.write(
            to: file,
            atomically: true,
            encoding: .utf8
        )
        let scanner = SessionScanner(sessionsURL: sessions, cacheURL: cache)

        let first = try scanner.scan(force: false)
        let second = try scanner.scan(force: false)
        try FileManager.default.removeItem(at: sessions)
        let unavailable = try scanner.scan(force: false)

        XCTAssertTrue(first.changed)
        XCTAssertFalse(second.changed)
        XCTAssertFalse(unavailable.changed)
        XCTAssertEqual(first.sessions, second.sessions)
        XCTAssertEqual(first.sessions, unavailable.sessions)
        XCTAssertTrue(FileManager.default.fileExists(atPath: cache.path))
    }
}
