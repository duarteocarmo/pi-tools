import AppKit

@MainActor
final class MenuController: NSObject, NSMenuDelegate, NSMenuItemValidation {
    private let store: StatsStore
    private let currencyStore: CurrencyStore
    private let updateStore: UpdateStore
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private var refreshTimer: Timer?
    private var selectedTab = DashboardTab(
        rawValue: UserDefaults.standard.string(forKey: "selectedTab") ?? ""
    ) ?? .models

    private var headerView: SummaryHeaderView?
    private var rangeView: RangePickerView?
    private var overviewView: OverviewView?
    private var spendView: DailySpendChartView?
    private var tabView: TabPickerView?
    private var barsView: BarListView?
    private var refreshItem: NSMenuItem?
    private var updateItem: NSMenuItem?
    private var sharingPicker: NSSharingServicePicker?
    private var settingsController: SettingsWindowController?

    init(store: StatsStore, currencyStore: CurrencyStore, updateStore: UpdateStore) {
        self.store = store
        self.currencyStore = currencyStore
        self.updateStore = updateStore
        super.init()

        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        statusItem.button?.image = PiMenuIcon.image()
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.title = ""
        statusItem.button?.toolTip = "Pi Helicopter"
        statusItem.button?.setAccessibilityLabel("Pi Helicopter usage")

        store.onChange = { [weak self] in self?.storeChanged() }
        currencyStore.onChange = { [weak self] in self?.currencyChanged() }
        updateStore.onChange = { [weak self] in self?.updateChanged() }
        store.refresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.store.refresh()
                self?.updateStore.checkIfNeeded()
            }
        }
    }

    func applicationDidBecomeActive() {
        settingsController?.sync()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu.numberOfItems == 0 {
            rebuildMenu()
        } else {
            updatePresentedSummary()
            if let updateItem { configureUpdateItem(updateItem) }
        }
        if let lastUpdated = store.lastUpdated, Date().timeIntervalSince(lastUpdated) > 60 {
            store.refresh()
        }
        updateStore.checkIfNeeded()
    }

    private func storeChanged() {
        guard menu.numberOfItems > 0 else { return }
        updatePresentedSummary()
    }

    private func currencyChanged() {
        settingsController?.sync()
        guard menu.numberOfItems > 0 else { return }
        updatePresentedSummary()
    }

    private func updateChanged() {
        guard let updateItem else { return }
        configureUpdateItem(updateItem)
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        let summary = store.summary(for: store.selectedRange)
        let today = store.summary(for: .day)

        let header = SummaryHeaderView(
            range: store.selectedRange,
            isRefreshing: store.isRefreshing,
            error: store.error,
            lastUpdated: store.lastUpdated
        )
        headerView = header
        menu.addItem(viewItem(for: header))

        let rangePicker = RangePickerView(selected: store.selectedRange) { [weak self] range in
            self?.select(range: range)
        }
        rangeView = rangePicker
        menu.addItem(viewItem(for: rangePicker))

        menu.addItem(.separator())

        let overview = OverviewView(summary: summary, today: today, money: currencyStore.money)
        overviewView = overview
        menu.addItem(viewItem(for: overview))

        let spend = DailySpendChartView(
            data: summary.dailySpend,
            range: store.selectedRange,
            money: currencyStore.money
        )
        spendView = spend
        menu.addItem(viewItem(for: spend))
        menu.addItem(.separator())

        let tabPicker = TabPickerView(selected: selectedTab) { [weak self] tab in
            self?.select(tab: tab)
        }
        tabView = tabPicker
        menu.addItem(viewItem(for: tabPicker))

        let bars = BarListView(tab: selectedTab, summary: summary, money: currencyStore.money)
        barsView = bars
        menu.addItem(viewItem(for: bars))
        menu.addItem(.separator())

        let refresh = NSMenuItem(title: "Refresh", action: #selector(refresh(_:)), keyEquivalent: "r")
        refresh.target = self
        refresh.isEnabled = !store.isRefreshing
        refreshItem = refresh
        menu.addItem(refresh)

        let share = viewItem(for: makeShareView(), isEnabled: true)
        share.title = "Share Snapshot…"
        menu.addItem(share)

        let settings = NSMenuItem(
            title: "Settings…",
            action: #selector(showSettings(_:)),
            keyEquivalent: ","
        )
        settings.target = self
        menu.addItem(settings)

        let update = NSMenuItem(
            title: "",
            action: #selector(showUpdate(_:)),
            keyEquivalent: ""
        )
        update.target = self
        configureUpdateItem(update)
        updateItem = update
        menu.addItem(update)
        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Quit Pi Helicopter",
            action: #selector(quit(_:)),
            keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)
    }

    private func select(range: DateRange) {
        store.selectedRange = range
        updatePresentedSummary()
    }

    private func select(tab: DashboardTab) {
        selectedTab = tab
        UserDefaults.standard.set(tab.rawValue, forKey: "selectedTab")
        updatePresentedSummary()
    }

    private func updatePresentedSummary() {
        let summary = store.summary(for: store.selectedRange)
        let today = store.summary(for: .day)
        rangeView?.select(range: store.selectedRange)
        tabView?.select(tab: selectedTab)
        headerView?.update(
            range: store.selectedRange,
            isRefreshing: store.isRefreshing,
            error: store.error,
            lastUpdated: store.lastUpdated
        )
        overviewView?.update(summary: summary, today: today, money: currencyStore.money)
        spendView?.update(
            data: summary.dailySpend,
            range: store.selectedRange,
            money: currencyStore.money
        )
        barsView?.update(tab: selectedTab, summary: summary, money: currencyStore.money)
        refreshItem?.isEnabled = !store.isRefreshing
    }

    private func viewItem(for view: NSView, isEnabled: Bool = false) -> NSMenuItem {
        let item = NSMenuItem()
        item.isEnabled = isEnabled
        item.view = view
        return item
    }

    private func makeShareView() -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: MenuStyle.width, height: 28))
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: MenuStyle.width).isActive = true
        view.heightAnchor.constraint(equalToConstant: 28).isActive = true

        let button = NSButton(title: "Share Snapshot…", target: self, action: #selector(shareSnapshot(_:)))
        button.alignment = .left
        button.bezelStyle = .inline
        button.font = NSFont.menuFont(ofSize: 0)
        button.attributedTitle = NSAttributedString(
            string: "Share Snapshot…",
            attributes: [
                .font: NSFont.menuFont(ofSize: 0),
                .foregroundColor: NSColor.labelColor
            ]
        )
        button.contentTintColor = .labelColor
        button.image = NSImage(
            systemSymbolName: "square.and.arrow.up",
            accessibilityDescription: "Share"
        )
        button.imagePosition = .imageLeading
        button.isBordered = false
        button.setAccessibilityLabel("Share snapshot")
        button.sendAction(on: .leftMouseDown)
        button.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(button)
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            button.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            button.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        return view
    }

    private func configureUpdateItem(_ item: NSMenuItem) {
        guard let version = updateStore.availableVersion else {
            item.isHidden = true
            return
        }
        item.title = "Update Available: \(version)…"
        item.isHidden = false
    }

    @objc func refresh(_ sender: Any?) {
        store.refresh()
        currencyStore.refreshIfNeeded()
    }

    @objc private func shareSnapshot(_ sender: NSButton) {
        let image = DashboardSnapshotRenderer.image(for: DashboardSnapshotContent(
            summary: store.summary(for: store.selectedRange),
            today: store.summary(for: .day),
            range: store.selectedRange,
            tab: selectedTab,
            money: currencyStore.money,
            isRefreshing: store.isRefreshing,
            error: store.error,
            lastUpdated: store.lastUpdated
        ))
        let picker = NSSharingServicePicker(items: [image])
        sharingPicker = picker
        menu.cancelTrackingWithoutAnimation()
        NSApp.activate(ignoringOtherApps: true)
        guard let button = statusItem.button else { return }
        picker.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    @objc func showSettings(_ sender: Any?) {
        if settingsController == nil {
            settingsController = SettingsWindowController(
                currencyStore: currencyStore,
                sessionsURL: store.sessionsURL
            )
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsController?.showWindow(sender)
    }

    @objc func openProjectWebsite(_ sender: Any?) {
        guard let url = URL(string: "https://github.com/duarteocarmo/pi-tools/tree/master/packages/pi-helicopter")
        else { return }
        NSWorkspace.shared.open(url)
    }

    @objc func quit(_ sender: Any?) {
        NSApp.terminate(nil)
    }

    @objc func chooseRange(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String,
              let range = DateRange(rawValue: value)
        else { return }
        select(range: range)
    }

    @objc func chooseTab(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String,
              let tab = DashboardTab(rawValue: value)
        else { return }
        select(tab: tab)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(refresh(_:)) { return !store.isRefreshing }
        if menuItem.action == #selector(chooseRange(_:)) {
            menuItem.state = menuItem.representedObject as? String == store.selectedRange.rawValue
                ? .on
                : .off
        }
        if menuItem.action == #selector(chooseTab(_:)) {
            menuItem.state = menuItem.representedObject as? String == selectedTab.rawValue
                ? .on
                : .off
        }
        return true
    }

    @objc private func showUpdate(_ sender: NSMenuItem) {
        guard let version = updateStore.availableVersion else { return }
        let command = "brew upgrade --cask pi-helicopter"
        let alert = NSAlert()
        alert.messageText = "Pi Helicopter \(version) is available"
        alert.informativeText = "Run this command in Terminal:\n\n\(command)"
        alert.addButton(withTitle: "Copy Command")
        alert.addButton(withTitle: "Not Now")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
    }

}

final class SummaryHeaderView: NSView {
    private let statusLabel = NSTextField(labelWithString: "")

    init(range: DateRange, isRefreshing: Bool, error: String?, lastUpdated: Date?) {
        super.init(frame: NSRect(x: 0, y: 0, width: MenuStyle.width, height: 40))
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: MenuStyle.width).isActive = true
        heightAnchor.constraint(equalToConstant: 40).isActive = true

        let title = NSTextField(labelWithString: "Pi Helicopter")
        title.font = MenuStyle.title
        statusLabel.font = MenuStyle.metadata
        for view in [title, statusLabel] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: MenuStyle.padding),
            title.centerYAnchor.constraint(equalTo: centerYAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -MenuStyle.padding),
            statusLabel.firstBaselineAnchor.constraint(equalTo: title.firstBaselineAnchor)
        ])
        title.setAccessibilityLabel("Pi Helicopter")
        statusLabel.setAccessibilityLabel("Refresh status")
        update(
            range: range,
            isRefreshing: isRefreshing,
            error: error,
            lastUpdated: lastUpdated
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(
        range: DateRange,
        isRefreshing: Bool,
        error: String?,
        lastUpdated: Date?,
        now: Date = Date()
    ) {
        statusLabel.stringValue = Self.statusTitle(
            range: range,
            isRefreshing: isRefreshing,
            error: error,
            lastUpdated: lastUpdated,
            now: now
        )
        statusLabel.textColor = error == nil ? .secondaryLabelColor : .systemRed
        statusLabel.toolTip = error
        statusLabel.setAccessibilityValue(error ?? statusLabel.stringValue.lowercased())
        statusLabel.setAccessibilityHelp(error)
    }

    static func statusTitle(
        range: DateRange,
        isRefreshing: Bool,
        error: String?,
        lastUpdated: Date?,
        now: Date
    ) -> String {
        if error != nil { return "ERROR" }
        if isRefreshing { return "REFRESHING" }
        guard let lastUpdated else { return range.title.uppercased() }

        let seconds = max(Int(now.timeIntervalSince(lastUpdated)), 0)
        if seconds < 60 { return "UPDATED NOW" }
        if seconds < 3_600 { return "UPDATED \(seconds / 60)M AGO" }
        if seconds < 86_400 { return "UPDATED \(seconds / 3_600)H AGO" }
        return "UPDATED \(seconds / 86_400)D AGO"
    }
}

final class RangePickerView: NSView {
    private let control: NSSegmentedControl
    private let onChange: (DateRange) -> Void

    init(selected: DateRange, onChange: @escaping (DateRange) -> Void) {
        self.onChange = onChange
        control = NSSegmentedControl(
            labels: DateRange.allCases.map(\.shortTitle),
            trackingMode: .selectOne,
            target: nil,
            action: nil
        )
        super.init(frame: NSRect(
            x: 0,
            y: 0,
            width: MenuStyle.width,
            height: MenuStyle.pickerHeight
        ))
        configure(control: control, accessibilityLabel: "Summary range")
        control.target = self
        control.action = #selector(changeRange(_:))
        select(range: selected)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func select(range: DateRange) {
        control.selectedSegment = DateRange.allCases.firstIndex(of: range) ?? 0
    }

    @objc private func changeRange(_ sender: NSSegmentedControl) {
        guard DateRange.allCases.indices.contains(sender.selectedSegment) else { return }
        onChange(DateRange.allCases[sender.selectedSegment])
    }

    private func configure(control: NSSegmentedControl, accessibilityLabel: String) {
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: MenuStyle.width).isActive = true
        heightAnchor.constraint(equalToConstant: MenuStyle.pickerHeight).isActive = true
        control.controlSize = MenuStyle.controlSize
        control.segmentStyle = .rounded
        control.translatesAutoresizingMaskIntoConstraints = false
        control.setAccessibilityLabel(accessibilityLabel)
        addSubview(control)
        NSLayoutConstraint.activate([
            control.leadingAnchor.constraint(equalTo: leadingAnchor, constant: MenuStyle.padding),
            control.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -MenuStyle.padding),
            control.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
}

final class TabPickerView: NSView {
    private let control: NSSegmentedControl
    private let onChange: (DashboardTab) -> Void

    init(selected: DashboardTab, onChange: @escaping (DashboardTab) -> Void) {
        let symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        let images = DashboardTab.allCases.map { tab in
            let image = NSImage(
                systemSymbolName: tab.symbolName,
                accessibilityDescription: tab.title
            ) ?? NSImage()
            return image.withSymbolConfiguration(symbolConfiguration) ?? image
        }
        self.onChange = onChange
        control = NSSegmentedControl(
            images: images,
            trackingMode: .selectOne,
            target: nil,
            action: nil
        )
        super.init(frame: NSRect(
            x: 0,
            y: 0,
            width: MenuStyle.width,
            height: MenuStyle.pickerHeight
        ))
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: MenuStyle.width).isActive = true
        heightAnchor.constraint(equalToConstant: MenuStyle.pickerHeight).isActive = true
        control.controlSize = MenuStyle.controlSize
        control.segmentStyle = .rounded
        control.target = self
        control.action = #selector(changeTab(_:))
        let segmentWidth = MenuStyle.contentWidth / CGFloat(DashboardTab.allCases.count)
        for (index, tab) in DashboardTab.allCases.enumerated() {
            control.setWidth(segmentWidth, forSegment: index)
            control.setToolTip(tab.title, forSegment: index)
        }
        control.translatesAutoresizingMaskIntoConstraints = false
        control.setAccessibilityLabel("Ranking category")
        addSubview(control)
        NSLayoutConstraint.activate([
            control.leadingAnchor.constraint(equalTo: leadingAnchor, constant: MenuStyle.padding),
            control.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -MenuStyle.padding),
            control.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        select(tab: selected)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func select(tab: DashboardTab) {
        control.selectedSegment = DashboardTab.allCases.firstIndex(of: tab) ?? 0
    }

    @objc private func changeTab(_ sender: NSSegmentedControl) {
        guard DashboardTab.allCases.indices.contains(sender.selectedSegment) else { return }
        onChange(DashboardTab.allCases[sender.selectedSegment])
    }
}

private enum PiMenuIcon {
    static func image() -> NSImage {
        let image = NSImage(size: NSSize(width: 16, height: 16))
        image.lockFocus()
        let mark = NSBezierPath()
        mark.move(to: NSPoint(x: 1, y: 14))
        mark.line(to: NSPoint(x: 15, y: 14))
        mark.line(to: NSPoint(x: 13.7, y: 11.8))
        mark.line(to: NSPoint(x: 12, y: 11.8))
        mark.line(to: NSPoint(x: 12, y: 5.2))
        mark.curve(
            to: NSPoint(x: 14.2, y: 2.7),
            controlPoint1: NSPoint(x: 12, y: 3.5),
            controlPoint2: NSPoint(x: 12.8, y: 2.7)
        )
        mark.line(to: NSPoint(x: 14.7, y: 2.7))
        mark.line(to: NSPoint(x: 14.7, y: 0.8))
        mark.line(to: NSPoint(x: 13.6, y: 0.8))
        mark.curve(
            to: NSPoint(x: 9.6, y: 5.4),
            controlPoint1: NSPoint(x: 11.2, y: 0.8),
            controlPoint2: NSPoint(x: 9.6, y: 2.6)
        )
        mark.line(to: NSPoint(x: 9.6, y: 11.8))
        mark.line(to: NSPoint(x: 7, y: 11.8))
        mark.line(to: NSPoint(x: 7, y: 0.8))
        mark.line(to: NSPoint(x: 4.2, y: 0.8))
        mark.line(to: NSPoint(x: 4.2, y: 11.8))
        mark.line(to: NSPoint(x: 1, y: 11.8))
        mark.close()
        NSColor.black.setFill()
        mark.fill()
        image.unlockFocus()
        image.isTemplate = true
        return image
    }
}
