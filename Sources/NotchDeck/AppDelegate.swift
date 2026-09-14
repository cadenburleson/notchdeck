import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: AppStore!
    private var pomodoro: PomodoroEngine!
    private var notchController: NotchWindowController!
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        store = AppStore.load()
        pomodoro = PomodoroEngine(settings: { [weak store] in store?.settings.pomodoro ?? PomodoroSettings() })
        notchController = NotchWindowController(store: store, pomodoro: pomodoro)
        notchController.show()
        setupStatusItem()
        NotificationService.shared.requestAuthorizationIfPossible()
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.saveNow()
    }

    // MARK: - Menu bar item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: "NotchDeck")
            button.image?.isTemplate = true
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    private func rebuildMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        let toggle = NSMenuItem(title: notchController.isVisible ? "Hide NotchDeck" : "Show NotchDeck",
                                action: #selector(toggleVisibility), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)

        let pin = NSMenuItem(title: "Keep Open", action: #selector(togglePinned), keyEquivalent: "")
        pin.target = self
        pin.state = notchController.viewModel.isPinned ? .on : .off
        menu.addItem(pin)

        menu.addItem(.separator())

        for tab in NotchTab.allCases {
            let item = NSMenuItem(title: "Open \(tab.title)", action: #selector(openTab(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = tab.rawValue
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let placement = NSMenuItem(title: "Placement", action: nil, keyEquivalent: "")
        let placementMenu = NSMenu()
        for edge in NotchEdge.allCases {
            let item = NSMenuItem(title: edge.title, action: #selector(setEdge(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = edge.rawValue
            item.state = store.settings.edge == edge ? .on : .off
            placementMenu.addItem(item)
        }
        placement.submenu = placementMenu
        menu.addItem(placement)

        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        login.state = LaunchAtLogin.isEnabled ? .on : .off
        login.isEnabled = LaunchAtLogin.isAvailable
        menu.addItem(login)

        let about = NSMenuItem(title: "About NotchDeck", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit NotchDeck", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    @objc private func toggleVisibility() {
        notchController.isVisible ? notchController.hide() : notchController.show()
    }

    @objc private func togglePinned() {
        notchController.setPinned(!notchController.viewModel.isPinned)
    }

    @objc private func openTab(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let tab = NotchTab(rawValue: raw) else { return }
        notchController.open(tab: tab)
    }

    @objc private func setEdge(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let edge = NotchEdge(rawValue: raw) else { return }
        store.settings.edge = edge
    }

    @objc private func toggleLaunchAtLogin() {
        LaunchAtLogin.isEnabled.toggle()
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "NotchDeck",
            .applicationVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev",
            .credits: NSAttributedString(string: "Notes, tasks and a pomodoro timer living in your MacBook's notch.\nhttps://github.com/cadenburleson/notchdeck"),
        ])
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu(menu)
    }
}

// MARK: - Launch at login

enum LaunchAtLogin {
    /// SMAppService only works from inside a real .app bundle, not `swift run`.
    static var isAvailable: Bool { Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app" }

    static var isEnabled: Bool {
        get { isAvailable && SMAppService.mainApp.status == .enabled }
        set {
            guard isAvailable else { return }
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("LaunchAtLogin error: \(error)")
            }
        }
    }
}
