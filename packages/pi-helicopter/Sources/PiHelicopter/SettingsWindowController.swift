import AppKit
import ServiceManagement

@MainActor
enum LaunchAtLogin {
    static var settingsTitle: String {
        SMAppService.mainApp.status == .requiresApproval
            ? "Launch at login (needs approval)"
            : "Launch at login"
    }

    static var state: NSControl.StateValue {
        switch SMAppService.mainApp.status {
        case .enabled: .on
        case .requiresApproval: .mixed
        default: .off
        }
    }

    static func toggle() throws {
        switch SMAppService.mainApp.status {
        case .enabled:
            try SMAppService.mainApp.unregister()
        case .requiresApproval:
            openSystemSettings()
        default:
            try SMAppService.mainApp.register()
        }
    }

    static func openSystemSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}

@MainActor
final class SettingsWindowController: NSWindowController {
    private let currencyStore: CurrencyStore
    private let sessionsURL: URL
    private let currencyPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let launchCheckbox = NSButton(
        checkboxWithTitle: "Launch at login",
        target: nil,
        action: nil
    )

    init(currencyStore: CurrencyStore, sessionsURL: URL) {
        self.currencyStore = currencyStore
        self.sessionsURL = sessionsURL

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 340),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)
        window.title = "Settings"
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("PiHelicopterSettingsAndAbout")
        configureContent()
        sync()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        sync()
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
    }

    func sync() {
        if let item = currencyPopup.itemArray.first(where: {
            $0.representedObject as? String == currencyStore.selected.rawValue
        }) {
            currencyPopup.select(item)
        }
        launchCheckbox.title = LaunchAtLogin.settingsTitle
        launchCheckbox.state = LaunchAtLogin.state
        launchCheckbox.allowsMixedState = true
        launchCheckbox.toolTip = SMAppService.mainApp.status == .requiresApproval
            ? "Select to open Login Items in System Settings."
            : nil
    }

    private func configureContent() {
        guard let contentView = window?.contentView else { return }

        currencyPopup.target = self
        currencyPopup.action = #selector(selectCurrency(_:))
        currencyPopup.setAccessibilityLabel("Display currency")
        for currency in DisplayCurrency.allCases {
            currencyPopup.addItem(withTitle: currency.menuTitle)
            currencyPopup.lastItem?.representedObject = currency.rawValue
        }

        launchCheckbox.target = self
        launchCheckbox.action = #selector(toggleLaunchAtLogin(_:))
        launchCheckbox.setAccessibilityLabel("Launch Pi Helicopter at login")

        let currencyLabel = NSTextField(labelWithString: "Currency:")
        currencyLabel.alignment = .right
        let launchSpacer = NSView()
        let grid = NSGridView(views: [
            [currencyLabel, currencyPopup],
            [launchSpacer, launchCheckbox]
        ])
        grid.rowSpacing = 12
        grid.columnSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .leading
        let generalSection = section(title: "General", views: [grid])

        let pathControl = NSPathControl(frame: .zero)
        pathControl.url = sessionsURL
        pathControl.pathStyle = .standard
        pathControl.setAccessibilityLabel("Pi sessions folder")
        pathControl.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let showFolder = NSButton(
            title: "Show in Finder",
            target: self,
            action: #selector(showSessionsFolder(_:))
        )
        showFolder.bezelStyle = .rounded

        let pathRow = NSStackView(views: [pathControl, showFolder])
        pathRow.orientation = .horizontal
        pathRow.alignment = .centerY
        pathRow.spacing = 10
        let dataSection = section(title: "Session Data", views: [pathRow])

        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "0.0.0"
        let appIcon = NSImageView(image: NSApp.applicationIconImage)
        appIcon.imageScaling = .scaleProportionallyUpOrDown
        appIcon.setAccessibilityLabel("Pi Helicopter app icon")

        let appName = NSTextField(labelWithString: "Pi Helicopter")
        appName.font = .systemFont(ofSize: 14, weight: .semibold)
        let versionLabel = NSTextField(labelWithString: "Version \(version)")
        versionLabel.textColor = .secondaryLabelColor
        let details = NSTextField(
            wrappingLabelWithString: "Local Pi usage. Exchange rates come from the European Central Bank. No telemetry."
        )
        details.textColor = .secondaryLabelColor
        let aboutDetails = NSStackView(views: [appName, versionLabel, details])
        aboutDetails.orientation = .vertical
        aboutDetails.alignment = .leading
        aboutDetails.spacing = 3

        let aboutRow = NSStackView(views: [appIcon, aboutDetails])
        aboutRow.orientation = .horizontal
        aboutRow.alignment = .top
        aboutRow.spacing = 12
        let aboutSection = section(title: "About", views: [aboutRow])

        let stack = NSStackView(views: [generalSection, dataSection, aboutSection])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -24),
            generalSection.widthAnchor.constraint(equalTo: stack.widthAnchor),
            dataSection.widthAnchor.constraint(equalTo: stack.widthAnchor),
            aboutSection.widthAnchor.constraint(equalTo: stack.widthAnchor),
            pathRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            aboutRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            currencyPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 150),
            pathControl.heightAnchor.constraint(equalToConstant: 24),
            appIcon.widthAnchor.constraint(equalToConstant: 48),
            appIcon.heightAnchor.constraint(equalToConstant: 48)
        ])
    }

    private func section(title: String, views: [NSView]) -> NSStackView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        let stack = NSStackView(views: [titleLabel] + views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        return stack
    }

    @objc private func selectCurrency(_ sender: NSPopUpButton) {
        guard let value = sender.selectedItem?.representedObject as? String,
              let currency = DisplayCurrency(rawValue: value)
        else { return }
        currencyStore.select(currency: currency)
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSButton) {
        do {
            try LaunchAtLogin.toggle()
            sync()
        } catch {
            guard let window else { return }
            NSAlert(error: error).beginSheetModal(for: window)
        }
    }

    @objc private func showSessionsFolder(_ sender: Any?) {
        showInFinder(url: sessionsURL)
    }
}

@MainActor
func showInFinder(url: URL) {
    var isDirectory: ObjCBool = false
    if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
       isDirectory.boolValue {
        NSWorkspace.shared.activateFileViewerSelecting([url])
        return
    }

    var existingParent = url.deletingLastPathComponent()
    while existingParent.path != "/",
          !FileManager.default.fileExists(atPath: existingParent.path) {
        existingParent.deleteLastPathComponent()
    }
    NSWorkspace.shared.open(existingParent)
}
