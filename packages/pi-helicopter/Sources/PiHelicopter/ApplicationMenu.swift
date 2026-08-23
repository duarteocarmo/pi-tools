import AppKit

@MainActor
enum ApplicationMenu {
    static func install(target: MenuController) {
        let appName = "Pi Helicopter"
        let mainMenu = NSMenu(title: "Main Menu")

        let appMenu = NSMenu(title: appName)
        addTopLevel(menu: appMenu, to: mainMenu)
        addItem(
            to: appMenu,
            title: "Settings…",
            action: #selector(MenuController.showSettings(_:)),
            keyEquivalent: ",",
            target: target
        )
        appMenu.addItem(.separator())
        let services = addItem(to: appMenu, title: "Services", action: nil)
        services.submenu = NSMenu(title: "Services")
        NSApp.servicesMenu = services.submenu
        appMenu.addItem(.separator())
        addItem(
            to: appMenu,
            title: "Hide \(appName)",
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h",
            target: NSApp
        )
        addItem(
            to: appMenu,
            title: "Hide Others",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h",
            modifiers: [.command, .option],
            target: NSApp
        )
        addItem(
            to: appMenu,
            title: "Show All",
            action: #selector(NSApplication.unhideAllApplications(_:)),
            target: NSApp
        )
        appMenu.addItem(.separator())
        addItem(
            to: appMenu,
            title: "Quit \(appName)",
            action: #selector(MenuController.quit(_:)),
            keyEquivalent: "q",
            target: target
        )

        let fileMenu = NSMenu(title: "File")
        addTopLevel(menu: fileMenu, to: mainMenu)
        addItem(
            to: fileMenu,
            title: "Close",
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        )

        let editMenu = NSMenu(title: "Edit")
        addTopLevel(menu: editMenu, to: mainMenu)
        addItem(to: editMenu, title: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        addItem(
            to: editMenu,
            title: "Redo",
            action: Selector(("redo:")),
            keyEquivalent: "z",
            modifiers: [.command, .shift]
        )
        editMenu.addItem(.separator())
        addItem(to: editMenu, title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        addItem(
            to: editMenu,
            title: "Copy",
            action: #selector(NSText.copy(_:)),
            keyEquivalent: "c"
        )
        addItem(to: editMenu, title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        addItem(
            to: editMenu,
            title: "Paste and Match Style",
            action: #selector(NSTextView.pasteAsPlainText(_:)),
            keyEquivalent: "v",
            modifiers: [.command, .option, .shift]
        )
        addItem(to: editMenu, title: "Delete", action: #selector(NSText.delete(_:)))
        addItem(
            to: editMenu,
            title: "Select All",
            action: #selector(NSResponder.selectAll(_:)),
            keyEquivalent: "a"
        )

        let viewMenu = NSMenu(title: "View")
        addTopLevel(menu: viewMenu, to: mainMenu)
        addItem(
            to: viewMenu,
            title: "Refresh",
            action: #selector(MenuController.refresh(_:)),
            keyEquivalent: "r",
            target: target
        )
        viewMenu.addItem(.separator())
        let rangeItem = addItem(to: viewMenu, title: "Date Range", action: nil)
        rangeItem.submenu = NSMenu(title: "Date Range")
        for (index, range) in DateRange.allCases.enumerated() {
            let item = addItem(
                to: rangeItem.submenu!,
                title: range.title,
                action: #selector(MenuController.chooseRange(_:)),
                keyEquivalent: String(index + 1),
                target: target
            )
            item.representedObject = range.rawValue
        }
        let rankingItem = addItem(to: viewMenu, title: "Ranking", action: nil)
        rankingItem.submenu = NSMenu(title: "Ranking")
        for tab in DashboardTab.allCases {
            let item = addItem(
                to: rankingItem.submenu!,
                title: tab.title,
                action: #selector(MenuController.chooseTab(_:)),
                target: target
            )
            item.representedObject = tab.rawValue
        }

        let windowMenu = NSMenu(title: "Window")
        addTopLevel(menu: windowMenu, to: mainMenu)
        addItem(
            to: windowMenu,
            title: "Minimize",
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m"
        )
        addItem(to: windowMenu, title: "Zoom", action: #selector(NSWindow.performZoom(_:)))
        windowMenu.addItem(.separator())
        addItem(
            to: windowMenu,
            title: "Bring All to Front",
            action: #selector(NSApplication.arrangeInFront(_:)),
            target: NSApp
        )
        NSApp.windowsMenu = windowMenu

        let helpMenu = NSMenu(title: "Help")
        addTopLevel(menu: helpMenu, to: mainMenu)
        addItem(
            to: helpMenu,
            title: "Pi Helicopter on GitHub",
            action: #selector(MenuController.openProjectWebsite(_:)),
            target: target
        )
        NSApp.helpMenu = helpMenu
        NSApp.mainMenu = mainMenu
    }

    @discardableResult
    private static func addItem(
        to menu: NSMenu,
        title: String,
        action: Selector?,
        keyEquivalent: String = "",
        modifiers: NSEvent.ModifierFlags? = nil,
        target: AnyObject? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        if let modifiers { item.keyEquivalentModifierMask = modifiers }
        item.target = target
        menu.addItem(item)
        return item
    }

    private static func addTopLevel(menu: NSMenu, to mainMenu: NSMenu) {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        mainMenu.addItem(item)
    }
}
