import AppKit

/// A transparent, non-activating panel anchored to the top-center of the primary display,
/// positioned to visually extend the physical notch.
final class NotchPanel: NSPanel {

    private let wingLeft: WingView
    private let wingRight: WingView
    private var notchFillView: NSView!
    private var trayView: TrayView?
    private var trayHeightConstraint: NSLayoutConstraint?
    private var isTrayOpen = false

    private weak var requestQueue: RequestQueue?
    private weak var agentRegistry: AgentRegistry?
    private weak var rulesStore: RulesStore?

    // Hotkey monitor
    private var hotkeyMonitor: Any?

    // Hover detection — use a single tracking area + mouse position verification
    private var hoverTrackingArea: NSTrackingArea?
    private var closeWorkItem: DispatchWorkItem?
    private var mouseMonitor: Any?

    /// Returns the built-in display (the one with the notch). Falls back to
    /// the main screen if no built-in display is found.
    static var builtInScreen: NSScreen {
        for screen in NSScreen.screens {
            let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
            if CGDisplayIsBuiltin(id) != 0 {
                return screen
            }
        }
        return NSScreen.main ?? NSScreen.screens[0]
    }

    /// Height of the collapsed wing bar — matches the macOS menu bar.
    /// On notch MacBooks, safeAreaInsets.top gives the full menu bar height
    /// (including the notch area). Falls back to NSStatusBar thickness on
    /// non-notch Macs.
    static let collapsedHeight: CGFloat = {
        let screen = builtInScreen
        if screen.safeAreaInsets.top > 0 {
            return screen.safeAreaInsets.top
        }
        return NSStatusBar.system.thickness
    }()

    // MARK: - Notch geometry helpers

    private static var notchWidth: CGFloat {
        let screen = builtInScreen
        // On notch MacBooks the safe area top inset > 0.
        // Compute notch width from the difference between the full screen
        // width and the visible (safe) frame width. The visible frame excludes
        // the notch region, so the notch width ≈ screen.frame.width − screen.visibleFrame.width
        // when menu bar is on top. However visibleFrame also excludes the Dock,
        // so we use auxiliaryTopLeftArea / auxiliaryTopRightArea instead.
        if screen.safeAreaInsets.top > 0 {
            if let left = screen.auxiliaryTopLeftArea,
               let right = screen.auxiliaryTopRightArea {
                let notchW = screen.frame.width - left.width - right.width
                return max(notchW, 0)
            }
            // Fallback: generous estimate
            return 250
        }
        return 0
    }

    private static var screenFrame: NSRect {
        builtInScreen.frame
    }

    // MARK: - Init

    init(requestQueue: RequestQueue, agentRegistry: AgentRegistry, rulesStore: RulesStore) {
        self.requestQueue = requestQueue
        self.agentRegistry = agentRegistry
        self.rulesStore = rulesStore

        self.wingLeft = WingView(side: .left)
        self.wingRight = WingView(side: .right)

        let screen = NotchPanel.builtInScreen
        let screenFrame = screen.frame
        // Full screen width, tall enough for menu bar + tray
        let panelFrame = NSRect(
            x: screenFrame.minX,
            y: screenFrame.maxY - NotchPanel.collapsedHeight,
            width: screenFrame.width,
            height: NotchPanel.collapsedHeight
        )

        super.init(contentRect: panelFrame,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)

        self.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.hidesOnDeactivate = false
        self.isMovable = false
        self.isMovableByWindowBackground = false
        self.acceptsMouseMovedEvents = true
        self.ignoresMouseEvents = false

        setupContentView()
        setupHotkey()

        requestQueue.addObserver(self)
        agentRegistry.addObserver(self)

        updateWings()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var canBecomeKey: Bool { true }

    deinit {
        if let monitor = hotkeyMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = mouseMonitor { NSEvent.removeMonitor(monitor) }
    }

    // MARK: - Layout

    private var wingLeftWidth: NSLayoutConstraint!
    private var wingRightWidth: NSLayoutConstraint!
    private var containerView: NSView!

    private func setupContentView() {
        let content = ClickThroughView(frame: self.frame)
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.clear.cgColor
        self.contentView = content
        containerView = content

        // Position wings relative to notch
        let screen = NotchPanel.builtInScreen
        let screenWidth = screen.frame.width
        let notchW = NotchPanel.notchWidth
        let notchCenterX = screenWidth / 2.0

        // Left wing: just to the left of the notch
        wingLeft.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(wingLeft)

        // Black fill in the notch gap — accepts mouse events so hover is stable
        let notchFill = NSView()
        notchFill.wantsLayer = true
        notchFill.layer?.backgroundColor = NSColor.black.cgColor
        notchFill.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(notchFill)
        self.notchFillView = notchFill

        // Right wing: just to the right of the notch
        wingRight.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(wingRight)

        wingLeftWidth = wingLeft.widthAnchor.constraint(equalToConstant: 0)
        wingRightWidth = wingRight.widthAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([
            // Left wing: right edge at notch left edge
            wingLeft.topAnchor.constraint(equalTo: content.topAnchor),
            wingLeft.heightAnchor.constraint(equalToConstant: NotchPanel.collapsedHeight),
            wingLeft.trailingAnchor.constraint(equalTo: content.leadingAnchor,
                                                constant: notchCenterX - notchW / 2.0),
            wingLeftWidth,

            // Right wing: left edge at notch right edge
            wingRight.topAnchor.constraint(equalTo: content.topAnchor),
            wingRight.heightAnchor.constraint(equalToConstant: NotchPanel.collapsedHeight),
            wingRight.leadingAnchor.constraint(equalTo: content.leadingAnchor,
                                                constant: notchCenterX + notchW / 2.0),
            wingRightWidth,

            // Black fill between wings (the notch gap)
            notchFill.topAnchor.constraint(equalTo: content.topAnchor),
            notchFill.heightAnchor.constraint(equalToConstant: NotchPanel.collapsedHeight),
            notchFill.leadingAnchor.constraint(equalTo: wingLeft.trailingAnchor),
            notchFill.trailingAnchor.constraint(equalTo: wingRight.leadingAnchor),
        ])

        // Add tracking area for hover on the wing region
        rebuildTrackingArea()
    }

    override func updateConstraintsIfNeeded() {
        super.updateConstraintsIfNeeded()
    }

    // MARK: - Wing expand/collapse

    private func setWingWidth(_ width: CGFloat, animated: Bool) {
        let targetWidth = width

        if animated {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.38
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.34, 1.28, 0.64, 1)
                ctx.allowsImplicitAnimation = true
                wingLeftWidth.constant = targetWidth
                wingRightWidth.constant = targetWidth
                containerView.layoutSubtreeIfNeeded()
            }, completionHandler: { [weak self] in
                guard let self = self else { return }
                if targetWidth > 0 {
                    // Fade in wing content after expand
                    NSAnimationContext.runAnimationGroup { ctx in
                        ctx.duration = 0.2
                        self.wingLeft.contentAlpha = 1.0
                        self.wingRight.contentAlpha = 1.0
                    }
                }
                self.rebuildTrackingArea()
            })
            if targetWidth == 0 {
                wingLeft.contentAlpha = 0.0
                wingRight.contentAlpha = 0.0
            }
        } else {
            wingLeftWidth.constant = targetWidth
            wingRightWidth.constant = targetWidth
            containerView.layoutSubtreeIfNeeded()
            wingLeft.contentAlpha = targetWidth > 0 ? 1.0 : 0.0
            wingRight.contentAlpha = targetWidth > 0 ? 1.0 : 0.0
            rebuildTrackingArea()
        }
    }

    // MARK: - Hover detection

    /// Builds a single tracking area covering the wing+notch region. When the
    /// mouse enters, we open the tray and start a global mouse-move monitor.
    /// The monitor checks the mouse position on every move — when the mouse
    /// leaves the entire interactive zone (wings + tray) for more than 0.3s,
    /// the tray closes. This avoids the flickering caused by separate
    /// tracking areas fighting each other.
    private func rebuildTrackingArea() {
        if let old = hoverTrackingArea {
            containerView.removeTrackingArea(old)
            hoverTrackingArea = nil
        }

        let screen = NotchPanel.builtInScreen
        let screenWidth = screen.frame.width
        let notchW = NotchPanel.notchWidth
        let notchCenterX = screenWidth / 2.0
        let leftW = wingLeftWidth.constant
        let rightW = wingRightWidth.constant

        guard leftW > 0 || rightW > 0 else { return }

        // Tracking rect covers both wings + notch gap (in contentView coords)
        let rect = NSRect(x: notchCenterX - notchW / 2.0 - leftW,
                          y: 0,
                          width: leftW + notchW + rightW,
                          height: NotchPanel.collapsedHeight)
        let ta = NSTrackingArea(rect: rect,
                                options: [.mouseEnteredAndExited, .activeAlways],
                                owner: self, userInfo: nil)
        containerView.addTrackingArea(ta)
        hoverTrackingArea = ta
    }

    /// Returns true if `screenPoint` is inside the interactive zone (wings or open tray).
    private func isMouseInsideInteractiveZone(_ screenPoint: NSPoint) -> Bool {
        // Convert screen point to contentView coords
        let windowPoint = convertPoint(fromScreen: screenPoint)
        let localPoint = containerView.convert(windowPoint, from: nil)

        // Check wings
        if wingLeft.frame.width > 0 && wingLeft.frame.contains(localPoint) { return true }
        if wingRight.frame.width > 0 && wingRight.frame.contains(localPoint) { return true }

        // Check notch fill between wings
        if notchFillView.frame.width > 0 && notchFillView.frame.contains(localPoint) { return true }

        // Check tray
        if isTrayOpen, let tray = trayView, tray.frame.contains(localPoint) { return true }

        return false
    }

    override func mouseEntered(with event: NSEvent) {
        cancelPendingClose()
        if !isTrayOpen { openTray() }
        startMouseMonitor()
    }

    override func mouseExited(with event: NSEvent) {
        scheduleCloseIfOutside()
    }

    private func startMouseMonitor() {
        guard mouseMonitor == nil else { return }
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            self?.checkMousePosition()
        }
    }

    private func stopMouseMonitor() {
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }
    }

    private func checkMousePosition() {
        let pos = NSEvent.mouseLocation
        if isMouseInsideInteractiveZone(pos) {
            cancelPendingClose()
        } else {
            scheduleCloseIfOutside()
        }
    }

    private func scheduleCloseIfOutside() {
        guard closeWorkItem == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.closeWorkItem = nil
            let pos = NSEvent.mouseLocation
            if !self.isMouseInsideInteractiveZone(pos) && self.isTrayOpen {
                self.closeTray()
                self.stopMouseMonitor()
            }
        }
        closeWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func cancelPendingClose() {
        closeWorkItem?.cancel()
        closeWorkItem = nil
    }

    // MARK: - Tray open/close

    func openTray() {
        guard !isTrayOpen else { return }
        guard let rq = requestQueue, let ar = agentRegistry, let rs = rulesStore else { return }
        isTrayOpen = true
        wingRight.setChevronUp(true)
        wingLeft.setCornerRadius(0)
        wingRight.setCornerRadius(0)

        let tray = TrayView(requestQueue: rq, agentRegistry: ar, rulesStore: rs)
        tray.onRequestResolved = { [weak self] in
            self?.handleRequestResolved()
        }
        tray.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(tray)
        self.trayView = tray

        let screen = NotchPanel.builtInScreen
        let screenWidth = screen.frame.width
        let trayCenterX = screenWidth / 2.0
        let notchW = NotchPanel.notchWidth
        let trayWidth = wingLeftWidth.constant + notchW + wingRightWidth.constant

        let heightConstraint = tray.heightAnchor.constraint(equalToConstant: 0)
        trayHeightConstraint = heightConstraint

        NSLayoutConstraint.activate([
            tray.topAnchor.constraint(equalTo: containerView.topAnchor, constant: NotchPanel.collapsedHeight),
            tray.widthAnchor.constraint(equalToConstant: trayWidth),
            tray.centerXAnchor.constraint(equalTo: containerView.leadingAnchor,
                                           constant: trayCenterX),
            heightConstraint,
        ])
        containerView.layoutSubtreeIfNeeded()

        // Expand panel to accommodate tray
        let contentHeight = tray.intrinsicContentSize.height
        let newPanelHeight = NotchPanel.collapsedHeight + contentHeight
        var panelFrame = self.frame
        panelFrame.origin.y = panelFrame.maxY - newPanelHeight
        panelFrame.size.height = newPanelHeight
        self.setFrame(panelFrame, display: true)

        // Overshoot target for bounce, then settle
        let overshootHeight = contentHeight * 1.04
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1.2)
            ctx.allowsImplicitAnimation = true
            heightConstraint.constant = overshootHeight
            containerView.layoutSubtreeIfNeeded()
        }, completionHandler: { [weak self] in
            guard let self = self else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.14
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                ctx.allowsImplicitAnimation = true
                heightConstraint.constant = contentHeight
                self.containerView.layoutSubtreeIfNeeded()
            }, completionHandler: nil)
        })
    }

    func closeTray() {
        guard isTrayOpen else { return }
        isTrayOpen = false
        wingRight.setChevronUp(false)
        wingLeft.setCornerRadius(16)
        wingRight.setCornerRadius(16)

        NSAnimationContext.runAnimationGroup({ [weak self] ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            ctx.allowsImplicitAnimation = true
            self?.trayHeightConstraint?.constant = 0
            self?.containerView.layoutSubtreeIfNeeded()
        }, completionHandler: { [weak self] in
            self?.trayView?.removeFromSuperview()
            self?.trayView = nil
            // Reset panel to menu bar height
            guard let self = self else { return }
            let screen = NotchPanel.builtInScreen
            let screenFrame = screen.frame
            let panelFrame = NSRect(
                x: screenFrame.minX,
                y: screenFrame.maxY - NotchPanel.collapsedHeight,
                width: screenFrame.width,
                height: NotchPanel.collapsedHeight
            )
            self.setFrame(panelFrame, display: true)
            self.rebuildTrackingArea()
        })
    }

    func toggleTray() {
        if isTrayOpen { closeTray() } else { openTray() }
    }

    // MARK: - Hotkey (⌥Space)

    private func setupHotkey() {
        hotkeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // ⌥Space
            if event.modifierFlags.contains(.option) && event.keyCode == 49 {
                DispatchQueue.main.async {
                    self?.toggleTray()
                }
            }
        }
    }

    // MARK: - Update wings from state

    func updateWings() {
        guard let rq = requestQueue, let ar = agentRegistry else { return }

        let agentCount = ar.count
        let pendingCount = rq.count
        let states = ar.allStates

        if agentCount == 0 {
            setWingWidth(0, animated: true)
        } else if wingLeftWidth.constant == 0 {
            setWingWidth(96, animated: true)
        }

        // Build dot states
        var dots: [WingView.DotState] = []
        for state in states {
            let hasPending = rq.requests.contains { $0.agent == state.agent.agent }
            if hasPending {
                dots.append(.waiting)
            } else if state.status != nil {
                dots.append(.running)
            } else {
                dots.append(.idle)
            }
        }

        wingLeft.updateDots(dots)
        wingLeft.updateBadge(count: pendingCount)

        // Refresh tray if open
        trayView?.reload()
    }

    // MARK: - Auto-close after action

    private func handleRequestResolved() {
        guard let rq = requestQueue else { return }
        if rq.count == 0 {
            // Auto-close tray after last pending is resolved
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.closeTray()
            }
        }
        updateWings()
    }

    // MARK: - New request pulse

    func pulseForNewRequest() {
        wingLeft.pulseAmberDot()
    }
}

// MARK: - RequestQueueObserver

extension NotchPanel: RequestQueueObserver {
    func requestQueueDidChange(_ queue: RequestQueue) {
        DispatchQueue.main.async { [weak self] in
            self?.updateWings()
        }
    }
}

// MARK: - AgentRegistryObserver

extension NotchPanel: AgentRegistryObserver {
    func agentRegistryDidChange(_ registry: AgentRegistry) {
        DispatchQueue.main.async { [weak self] in
            self?.updateWings()
        }
    }
}
