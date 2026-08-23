import AppKit

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuController: MenuController?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let controller = MenuController(
            store: StatsStore(),
            currencyStore: CurrencyStore(),
            updateStore: UpdateStore()
        )
        menuController = controller
        ApplicationMenu.install(target: controller)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        menuController?.applicationDidBecomeActive()
    }
}
