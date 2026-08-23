import AppKit

final class OverviewView: NSView {
    private var metrics: [(label: String, value: String)] = []

    override var isFlipped: Bool { true }

    init(summary: Summary, today: Summary, money: MoneyFormat = .usd) {
        super.init(frame: NSRect(x: 0, y: 0, width: MenuStyle.width, height: 112))
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: MenuStyle.width).isActive = true
        heightAnchor.constraint(equalToConstant: 112).isActive = true
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        update(summary: summary, today: today, money: money)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(summary: Summary, today: Summary, money: MoneyFormat = .usd) {
        let average = summary.daysActive > 0 ? summary.cost / Double(summary.daysActive) : 0
        metrics = [
            ("Total", money.money(summary.cost)),
            ("Sessions", Format.count(summary.sessionCount)),
            ("Messages", Format.count(summary.messageCount)),
            ("Active days", Format.count(summary.daysActive)),
            ("Avg/day", money.money(average)),
            ("Today", money.money(today.cost))
        ]
        setAccessibilityLabel("Usage overview")
        setAccessibilityValue(metrics.map { "\($0.label), \($0.value)" }.joined(separator: "; "))
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawText(
            "Overview",
            in: NSRect(x: 14, y: 8, width: MenuStyle.contentWidth, height: 17),
            font: MenuStyle.section,
            color: .labelColor
        )

        let columnWidth = MenuStyle.contentWidth / 3
        for (index, metric) in metrics.enumerated() {
            let column = index % 3
            let row = index / 3
            let x = CGFloat(14) + CGFloat(column) * columnWidth
            let y = CGFloat(29 + row * 40)
            drawText(
                metric.value,
                in: NSRect(x: x, y: y, width: columnWidth, height: 18),
                font: MenuStyle.value,
                color: .labelColor,
                alignment: .center
            )
            drawText(
                metric.label,
                in: NSRect(x: x, y: y + 19, width: columnWidth, height: 14),
                font: MenuStyle.caption,
                color: .secondaryLabelColor,
                alignment: .center
            )
        }

        for column in 1...2 {
            let x = CGFloat(14) + CGFloat(column) * columnWidth
            let separator = NSBezierPath()
            separator.move(to: NSPoint(x: x, y: 31))
            separator.line(to: NSPoint(x: x, y: 101))
            NSColor.separatorColor.withAlphaComponent(0.22).setStroke()
            separator.lineWidth = 0.5
            separator.stroke()
        }
    }
}

final class DailySpendChartView: NSView {
    private var data: [(day: String, cost: Double)] = []
    private var range = DateRange.week
    private var money = MoneyFormat.usd

    override var isFlipped: Bool { true }

    init(
        data: [(day: String, cost: Double)],
        range: DateRange,
        money: MoneyFormat = .usd
    ) {
        super.init(frame: NSRect(x: 0, y: 0, width: MenuStyle.width, height: 126))
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: MenuStyle.width).isActive = true
        heightAnchor.constraint(equalToConstant: 126).isActive = true
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        update(data: data, range: range, money: money)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(
        data: [(day: String, cost: Double)],
        range: DateRange,
        money: MoneyFormat = .usd
    ) {
        self.data = data
        self.range = range
        self.money = money
        let total = data.reduce(0) { $0 + $1.cost }
        let details = data.suffix(30).map { "\($0.day), \(money.money($0.cost))" }.joined(separator: "; ")
        setAccessibilityLabel("Daily spend for \(range.title)")
        setAccessibilityValue("\(money.money(total)) total. \(details)")
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let secondary = NSColor.secondaryLabelColor
        drawText(
            "Daily spend",
            in: NSRect(x: 14, y: 8, width: 150, height: 18),
            font: MenuStyle.section,
            color: .labelColor
        )
        drawText(
            "\(data.count) active days",
            in: NSRect(
                x: MenuStyle.width - MenuStyle.padding - 121,
                y: 9,
                width: 121,
                height: 16
            ),
            font: MenuStyle.metadata,
            color: secondary,
            alignment: .right
        )

        guard !data.isEmpty else {
            drawText(
                "No spend in this range",
                in: NSRect(x: 14, y: 58, width: MenuStyle.contentWidth, height: 18),
                font: MenuStyle.metadata,
                color: secondary,
                alignment: .center
            )
            return
        }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let dates = data.compactMap { dayDate(from: $0.day) }
        let start: Date
        if let days = range.days {
            start = calendar.date(byAdding: .day, value: -(days - 1), to: today) ?? today
        } else {
            start = dates.min() ?? today
        }
        let end = max(today, dates.max() ?? today)
        let daySpan = max(calendar.dateComponents([.day], from: start, to: end).day ?? 0, 0)
        let slotCount = max(daySpan + 1, 1)
        let maximum = max(data.map(\.cost).max() ?? 0, 0.0001)
        let plot = NSRect(
            x: 43,
            y: 31,
            width: MenuStyle.width - 43 - MenuStyle.padding,
            height: 70
        )

        for fraction in [0.0, 0.5, 1.0] {
            let y = plot.maxY - plot.height * fraction
            let path = NSBezierPath()
            path.move(to: NSPoint(x: plot.minX, y: y))
            path.line(to: NSPoint(x: plot.maxX, y: y))
            NSColor.separatorColor.withAlphaComponent(fraction == 0 ? 0.32 : 0.16).setStroke()
            path.lineWidth = 0.5
            path.stroke()
        }

        drawText(
            money.chartMoney(maximum),
            in: NSRect(x: 4, y: 27, width: 35, height: 14),
            font: MenuStyle.captionMono,
            color: secondary,
            alignment: .right
        )
        drawText(
            money.chartMoney(0),
            in: NSRect(x: 4, y: 94, width: 35, height: 14),
            font: MenuStyle.captionMono,
            color: secondary,
            alignment: .right
        )

        let slotWidth = plot.width / CGFloat(slotCount)
        let maximumBarWidth: CGFloat = switch range {
        case .day: 32
        case .week: 18
        default: 8
        }
        let barWidth = min(max(slotWidth * 0.62, 1.5), maximumBarWidth)
        let increaseContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        let color = NSColor.labelColor.withAlphaComponent(increaseContrast ? 0.92 : 0.68)
        color.setFill()

        for point in data {
            guard point.cost > 0, let date = dayDate(from: point.day) else { continue }
            let offset = calendar.dateComponents([.day], from: start, to: date).day ?? 0
            guard offset >= 0, offset < slotCount else { continue }
            let height = max(2, plot.height * point.cost / maximum)
            let x = plot.minX + CGFloat(offset) * slotWidth + (slotWidth - barWidth) / 2
            let rect = NSRect(x: x, y: plot.maxY - height, width: barWidth, height: height)
            let bar = NSBezierPath(roundedRect: rect, xRadius: min(2, barWidth / 2), yRadius: 2)
            bar.fill()
            if increaseContrast {
                NSColor.labelColor.setStroke()
                bar.lineWidth = 0.75
                bar.stroke()
                color.setFill()
            }
        }

        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        if slotCount == 1 {
            drawText(
                "Today",
                in: NSRect(x: plot.minX, y: 105, width: plot.width, height: 14),
                font: MenuStyle.caption,
                color: secondary,
                alignment: .center
            )
        } else {
            drawText(
                formatter.string(from: start),
                in: NSRect(x: plot.minX, y: 105, width: 90, height: 14),
                font: MenuStyle.caption,
                color: secondary
            )
            drawText(
                formatter.string(from: end),
                in: NSRect(x: plot.maxX - 90, y: 105, width: 90, height: 14),
                font: MenuStyle.caption,
                color: secondary,
                alignment: .right
            )
        }
    }
}

final class BarListView: NSView {
    private var tab = DashboardTab.models
    private var summary = Summary()
    private var money = MoneyFormat.usd

    override var isFlipped: Bool { true }

    init(tab: DashboardTab, summary: Summary, money: MoneyFormat = .usd) {
        super.init(frame: NSRect(x: 0, y: 0, width: MenuStyle.width, height: 255))
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: MenuStyle.width).isActive = true
        heightAnchor.constraint(equalToConstant: 255).isActive = true
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        update(tab: tab, summary: summary, money: money)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(tab: DashboardTab, summary: Summary, money: MoneyFormat = .usd) {
        self.tab = tab
        self.summary = summary
        self.money = money
        setAccessibilityLabel("\(tab.title) ranking")
        setAccessibilityValue(accessibilitySummary())
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let entries = rankedEntries()
        drawText(
            sectionTitle(),
            in: NSRect(x: 14, y: 8, width: 160, height: 18),
            font: MenuStyle.section,
            color: .labelColor
        )
        drawText(
            trailingTitle(),
            in: NSRect(
                x: MenuStyle.width - MenuStyle.padding - 111,
                y: 9,
                width: 111,
                height: 16
            ),
            font: MenuStyle.metadata,
            color: .secondaryLabelColor,
            alignment: .right
        )

        if entries.isEmpty {
            drawText(
                "No data",
                in: NSRect(x: 14, y: 80, width: MenuStyle.contentWidth, height: 18),
                font: MenuStyle.metadata,
                color: .secondaryLabelColor,
                alignment: .center
            )
        } else {
            for (index, entry) in entries.prefix(4).enumerated() {
                drawBar(entry: entry, y: CGFloat(34 + index * 46))
            }
        }
    }

    private func sectionTitle() -> String {
        tab == .tokens ? "Token usage" : "Top \(tab.title.lowercased())"
    }

    private func rankedEntries() -> [BarEntry] {
        switch tab {
        case .models:
            let maximum = max(summary.models.first?.primary ?? 0, 0.0001)
            return summary.models.map {
                BarEntry(
                    title: Format.modelName($0.name),
                    value: money.money($0.primary),
                    subtitle: "\(Format.count($0.count)) calls",
                    fraction: $0.primary / maximum
                )
            }
        case .projects:
            let maximum = max(summary.projects.first?.primary ?? 0, 0.0001)
            return summary.projects.map {
                BarEntry(
                    title: $0.name,
                    value: money.money($0.primary),
                    subtitle: "\(Format.count($0.count)) sessions",
                    fraction: $0.primary / maximum
                )
            }
        case .languages:
            let total = max(summary.languages.reduce(0) { $0 + $1.primary }, 1)
            let maximum = max(summary.languages.first?.primary ?? 0, 1)
            return summary.languages.map {
                BarEntry(
                    title: $0.name,
                    value: "\(Format.count(Int($0.primary))) lines",
                    subtitle: "\(Format.count($0.count)) edits, \(String(format: "%.0f", $0.primary / total * 100))%",
                    fraction: $0.primary / maximum
                )
            }
        case .tools:
            let total = max(summary.tools.reduce(0) { $0 + $1.count }, 1)
            let maximum = max(summary.tools.first?.count ?? 0, 1)
            return summary.tools.map {
                BarEntry(
                    title: $0.name,
                    value: "\(Format.count($0.count)) calls",
                    subtitle: "\(String(format: "%.0f", Double($0.count) / Double(total) * 100))% of tool calls",
                    fraction: Double($0.count) / Double(maximum)
                )
            }
        case .tokens:
            let total = summary.tokens.total
            let denominator = max(total, 1)
            let cached = summary.tokens.cacheRead + summary.tokens.cacheWrite
            return [
                BarEntry(
                    title: "Total",
                    value: Format.count(total),
                    subtitle: "All processed tokens",
                    fraction: Double(total) / Double(denominator)
                ),
                BarEntry(
                    title: "Cached",
                    value: Format.count(cached),
                    subtitle: "Read and write cache",
                    fraction: Double(cached) / Double(denominator)
                ),
                BarEntry(
                    title: "Input",
                    value: Format.count(summary.tokens.input),
                    subtitle: "Prompt tokens",
                    fraction: Double(summary.tokens.input) / Double(denominator)
                ),
                BarEntry(
                    title: "Output",
                    value: Format.count(summary.tokens.output),
                    subtitle: "Generated tokens",
                    fraction: Double(summary.tokens.output) / Double(denominator)
                )
            ]
        }
    }

    private func trailingTitle() -> String {
        switch tab {
        case .models, .projects: "by cost"
        case .languages: "by lines"
        case .tools: "by calls"
        case .tokens: "by volume"
        }
    }

    private func drawBar(entry: BarEntry, y: CGFloat) {
        drawText(
            entry.title,
            in: NSRect(
                x: 14,
                y: y,
                width: MenuStyle.contentWidth - 82,
                height: 16
            ),
            font: MenuStyle.primary,
            color: .labelColor
        )
        drawText(
            entry.value,
            in: NSRect(
                x: MenuStyle.width - MenuStyle.padding - 81,
                y: y,
                width: 81,
                height: 16
            ),
            font: MenuStyle.number,
            color: .labelColor,
            alignment: .right
        )
        drawTrack(fraction: entry.fraction, y: y + 19)
        drawText(
            entry.subtitle,
            in: NSRect(x: 14, y: y + 27, width: MenuStyle.contentWidth, height: 14),
            font: MenuStyle.caption,
            color: .secondaryLabelColor
        )
    }

    private func drawTrack(fraction: Double, y: CGFloat) {
        let track = NSRect(x: 14, y: y, width: MenuStyle.contentWidth, height: 5)
        NSColor.quaternaryLabelColor.setFill()
        NSBezierPath(roundedRect: track, xRadius: 2.5, yRadius: 2.5).fill()
        NSColor.labelColor.withAlphaComponent(0.68).setFill()
        let fill = NSRect(
            x: track.minX,
            y: track.minY,
            width: max(3, track.width * min(max(fraction, 0), 1)),
            height: track.height
        )
        NSBezierPath(roundedRect: fill, xRadius: 2.5, yRadius: 2.5).fill()
    }

    private func accessibilitySummary() -> String {
        let ranking = rankedEntries().prefix(10).map {
            "\($0.title), \($0.value), \($0.subtitle)"
        }.joined(separator: "; ")
        return ranking
    }

}

private struct BarEntry {
    let title: String
    let value: String
    let subtitle: String
    let fraction: Double
}

private func dayDate(from key: String) -> Date? {
    let parts = key.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3 else { return nil }
    return Calendar(identifier: .gregorian).date(from: DateComponents(
        year: parts[0],
        month: parts[1],
        day: parts[2]
    ))
}

private func drawText(
    _ text: String,
    in rect: NSRect,
    font: NSFont,
    color: NSColor,
    alignment: NSTextAlignment = .left
) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    paragraph.lineBreakMode = .byTruncatingTail
    NSString(string: text).draw(
        in: rect,
        withAttributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
    )
}
