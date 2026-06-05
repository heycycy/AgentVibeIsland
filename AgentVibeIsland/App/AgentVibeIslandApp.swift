import AppKit

@main
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var ipcServer: IPCServer!
    private var requestQueue: RequestQueue!
    private var rulesStore: RulesStore!
    private var agentRegistry: AgentRegistry!
    private var notchPanel: NotchPanel!

    // MARK: - Entry Point

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide from Dock — menu bar only
        NSApp.setActivationPolicy(.accessory)

        // Create menu bar status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.title = "🏝"
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Agent Vibe Island", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
        statusItem.menu = menu

        // Initialize core components
        requestQueue = RequestQueue()
        rulesStore = RulesStore()
        agentRegistry = AgentRegistry()

        // Create NotchPanel UI
        notchPanel = NotchPanel(requestQueue: requestQueue,
                                agentRegistry: agentRegistry,
                                rulesStore: rulesStore)
        notchPanel.orderFrontRegardless()

        // Set up system notifications
        let nm = NotificationManager.shared
        nm.agentRegistry = agentRegistry
        nm.isTrayOpen = { [weak self] in
            guard let panel = self?.notchPanel else { return false }
            return panel.frame.height > NotchPanel.collapsedHeight
        }
        nm.onAllowAction = { [weak self] requestId in
            let decision = PermissionDecision(requestId: requestId, decision: "allow")
            self?.requestQueue.resolve(requestId: requestId, decision: decision)
        }
        nm.onOpenTrayAction = { [weak self] in
            self?.notchPanel.openTray()
        }
        nm.requestPermission()

        // Start IPC server on a background thread
        ipcServer = IPCServer(requestQueue: requestQueue,
                              rulesStore: rulesStore,
                              agentRegistry: agentRegistry)
        ipcServer.onNewRequest = { [weak self] in
            DispatchQueue.main.async {
                self?.notchPanel.pulseForNewRequest()
            }
        }
        ipcServer.start()

        NSLog("AgentVibeIsland: App launched")
    }

    func applicationWillTerminate(_ notification: Notification) {
        ipcServer?.stop()
        NSLog("AgentVibeIsland: App terminated")
    }
}
