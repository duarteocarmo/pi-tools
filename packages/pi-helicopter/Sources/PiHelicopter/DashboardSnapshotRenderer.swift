import AppKit

struct DashboardSnapshotContent {
    let summary: Summary
    let today: Summary
    let range: DateRange
    let tab: DashboardTab
    let money: MoneyFormat
    let isRefreshing: Bool
    let error: String?
    let lastUpdated: Date?
}

@MainActor
enum DashboardSnapshotRenderer {
    static func image(
        for content: DashboardSnapshotContent,
        appearance: NSAppearance? = nil
    ) -> NSImage {
        let header = SummaryHeaderView(
            range: content.range,
            isRefreshing: content.isRefreshing,
            error: content.error,
            lastUpdated: content.lastUpdated
        )
        let range = RangePickerView(selected: content.range) { _ in }
        let overview = OverviewView(
            summary: content.summary,
            today: content.today,
            money: content.money
        )
        let spend = DailySpendChartView(
            data: content.summary.dailySpend,
            range: content.range,
            money: content.money
        )
        let tab = TabPickerView(selected: content.tab) { _ in }
        let bars = BarListView(
            tab: content.tab,
            summary: content.summary,
            money: content.money
        )
        let stack = NSStackView(views: [
            header,
            range,
            SnapshotSeparatorView(),
            overview,
            spend,
            SnapshotSeparatorView(),
            tab,
            bars
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0

        let size = NSSize(width: MenuStyle.width, height: stack.fittingSize.height)
        let card = SnapshotCardView(frame: NSRect(origin: .zero, size: size))
        card.appearance = appearance ?? NSApp.effectiveAppearance
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            stack.topAnchor.constraint(equalTo: card.topAnchor),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor)
        ])
        card.layoutSubtreeIfNeeded()

        let scale = 2
        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width) * scale,
            pixelsHigh: Int(size.height) * scale,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return NSImage(size: size) }
        representation.size = size
        card.cacheDisplay(in: card.bounds, to: representation)

        let image = NSImage(size: size)
        image.addRepresentation(representation)
        return image
    }
}

private final class SnapshotCardView: NSView {
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        NSColor.separatorColor.setStroke()
        let border = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 12, yRadius: 12)
        border.lineWidth = 1
        border.stroke()
    }
}

private final class SnapshotSeparatorView: NSView {
    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: MenuStyle.width, height: 12))
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: MenuStyle.width).isActive = true
        heightAnchor.constraint(equalToConstant: 12).isActive = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        let line = NSBezierPath()
        line.move(to: NSPoint(x: MenuStyle.padding, y: bounds.midY))
        line.line(to: NSPoint(x: bounds.width - MenuStyle.padding, y: bounds.midY))
        NSColor.separatorColor.setStroke()
        line.lineWidth = 0.5
        line.stroke()
    }
}
