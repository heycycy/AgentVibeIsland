import AppKit
import Carbon
import ServiceManagement

/// Floating preferences window with two tabs: Always Allow Rules and Settings.
final class RulesManagerWindow: NSPanel {

    private let rulesStore: RulesStore
    private weak var agentRegistry: AgentRegistry?
    private weak var requestQueue: RequestQueue?

    /// Callback to re-register the global hotkey after user changes it.
    var onHotkeyChanged: ((_ modifiers: NSEvent.ModifierFlags, _ keyCode: UInt16) -> Void)?

    private static var shared: RulesManagerWindow?

    // MARK: - Show singleton

    static func show(rulesStore: RulesStore, agentRegistry: AgentRegistry?, requestQueue: RequestQueue?) {
        if let existing = shared, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            return
        }
        let w = RulesManagerWindow(rulesStore: rulesStore, agentRegistry: agentRegistry, requestQueue: requestQueue)
        shared = w
        w.center()
        w.makeKeyAndOrderFront(nil)
    }

    // MARK: - Init

    private init(rulesStore: RulesStore, agentRegistry: AgentRegistry?, requestQueue: RequestQueue?) {
        self.rulesStore = rulesStore
        self.agentRegistry = agentRegistry
        self.requestQueue = requestQueue

        let frame = NSRect(x: 0, y: 0, width: 420, height: 540)
        super.init(contentRect: frame,
                   styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)

        self.title = "Agent Vibe Island — Preferences"
        self.minSize = NSSize(width: 380, height: 400)
        self.isMovableByWindowBackground = true
        self.backgroundColor = NSColor(red: 20/255, green: 20/255, blue: 20/255, alpha: 1)
        self.titlebarAppearsTransparent = true
        self.isReleasedWhenClosed = false
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.appearance = NSAppearance(named: .darkAqua)

        setupTabs()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Tab setup

    private func setupTabs() {
        let tabView = NSTabView()
        tabView.tabViewType = .topTabsBezelBorder
        tabView.translatesAutoresizingMaskIntoConstraints = false

        let rulesTab = NSTabViewItem(identifier: "rules")
        rulesTab.label = "Always Allow Rules"
        rulesTab.view = makeRulesTab()

        let settingsTab = NSTabViewItem(identifier: "settings")
        settingsTab.label = "Settings"
        settingsTab.view = makeSettingsTab()

        tabView.addTabViewItem(rulesTab)
        tabView.addTabViewItem(settingsTab)

        contentView = tabView
    }

    // MARK: =====================
    // MARK: TAB 1 — RULES
    // MARK: =====================

    private var rulesStackView: NSStackView!
    private var rulesCountLabel: NSTextField!
    private var activeFilter: String = "All"

    private func makeRulesTab() -> NSView {
        let container = NSView()
        container.wantsLayer = true

        // Header
        let headerRow = NSView()
        headerRow.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: "Always allow rules")
        titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        titleLabel.textColor = NSColor(white: 1, alpha: 0.85)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.isBordered = false
        titleLabel.drawsBackground = false
        headerRow.addSubview(titleLabel)

        let addBtn = makeSmallButton(title: "+ Add rule")
        addBtn.target = self
        addBtn.action = #selector(addRuleTapped)
        headerRow.addSubview(addBtn)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: headerRow.leadingAnchor, constant: 14),
            titleLabel.centerYAnchor.constraint(equalTo: headerRow.centerYAnchor),
            addBtn.trailingAnchor.constraint(equalTo: headerRow.trailingAnchor, constant: -14),
            addBtn.centerYAnchor.constraint(equalTo: headerRow.centerYAnchor),
            headerRow.heightAnchor.constraint(equalToConstant: 36),
        ])

        // Filter chips
        let chipRow = NSStackView()
        chipRow.orientation = .horizontal
        chipRow.spacing = 6
        chipRow.translatesAutoresizingMaskIntoConstraints = false
        for name in ["All", "Claude", "Cursor", "OpenAI"] {
            let chip = makeChipButton(title: name, active: name == "All")
            chip.target = self
            chip.action = #selector(filterChipTapped(_:))
            chipRow.addArrangedSubview(chip)
        }

        // Scroll view with rules stack
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        rulesStackView = NSStackView()
        rulesStackView.orientation = .vertical
        rulesStackView.alignment = .leading
        rulesStackView.spacing = 0
        rulesStackView.translatesAutoresizingMaskIntoConstraints = false

        let clipView = NSClipView()
        clipView.drawsBackground = false
        clipView.documentView = rulesStackView
        scrollView.contentView = clipView

        // Footer
        let footerRow = NSView()
        footerRow.translatesAutoresizingMaskIntoConstraints = false

        rulesCountLabel = NSTextField(labelWithString: "0 rules total")
        rulesCountLabel.font = NSFont.systemFont(ofSize: 10)
        rulesCountLabel.textColor = NSColor(white: 1, alpha: 0.25)
        rulesCountLabel.translatesAutoresizingMaskIntoConstraints = false
        rulesCountLabel.isBordered = false
        rulesCountLabel.drawsBackground = false
        footerRow.addSubview(rulesCountLabel)

        let removeDisabledBtn = makeSmallButton(title: "Remove disabled")
        removeDisabledBtn.target = self
        removeDisabledBtn.action = #selector(removeDisabledTapped)
        footerRow.addSubview(removeDisabledBtn)

        NSLayoutConstraint.activate([
            rulesCountLabel.leadingAnchor.constraint(equalTo: footerRow.leadingAnchor, constant: 14),
            rulesCountLabel.centerYAnchor.constraint(equalTo: footerRow.centerYAnchor),
            removeDisabledBtn.trailingAnchor.constraint(equalTo: footerRow.trailingAnchor, constant: -14),
            removeDisabledBtn.centerYAnchor.constraint(equalTo: footerRow.centerYAnchor),
            footerRow.heightAnchor.constraint(equalToConstant: 32),
        ])

        // Layout all
        for v in [headerRow, chipRow, scrollView, footerRow] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(v)
        }

        NSLayoutConstraint.activate([
            headerRow.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            headerRow.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            headerRow.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            chipRow.topAnchor.constraint(equalTo: headerRow.bottomAnchor, constant: 4),
            chipRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),

            scrollView.topAnchor.constraint(equalTo: chipRow.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: footerRow.topAnchor, constant: -4),

            rulesStackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            rulesStackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            rulesStackView.topAnchor.constraint(equalTo: clipView.topAnchor),

            footerRow.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            footerRow.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            footerRow.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4),
        ])

        reloadRules()
        return container
    }

    private func reloadRules() {
        rulesStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }

        var rules = rulesStore.allRules
        if activeFilter != "All" {
            let agentKey = activeFilter.lowercased()
            rules = rules.filter { $0.agent.lowercased().hasPrefix(agentKey.prefix(4).lowercased()) }
        }

        for rule in rules {
            let row = makeRuleRow(rule)
            rulesStackView.addArrangedSubview(row)
            row.leadingAnchor.constraint(equalTo: rulesStackView.leadingAnchor).isActive = true
            row.trailingAnchor.constraint(equalTo: rulesStackView.trailingAnchor).isActive = true
        }

        let total = rulesStore.allRules.count
        rulesCountLabel.stringValue = "\(total) rule\(total == 1 ? "" : "s") total"
    }

    private func makeRuleRow(_ rule: Rule) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.wantsLayer = true
        row.alphaValue = rule.enabled ? 1.0 : 0.4

        // Bottom border
        let border = NSView()
        border.wantsLayer = true
        border.layer?.backgroundColor = NSColor(white: 1, alpha: 0.06).cgColor
        border.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(border)

        // Agent dot
        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 4
        dot.layer?.backgroundColor = agentColor(for: rule.agent).cgColor
        dot.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(dot)

        // Body stack
        let actionLabel = NSTextField(labelWithString: actionDisplayName(rule.action))
        actionLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        actionLabel.textColor = NSColor(white: 1, alpha: 0.75)
        actionLabel.isBordered = false
        actionLabel.drawsBackground = false

        let scopeLabel = NSTextField(labelWithString: rule.scope)
        scopeLabel.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        scopeLabel.textColor = NSColor(white: 1, alpha: 0.35)
        scopeLabel.isBordered = false
        scopeLabel.drawsBackground = false
        scopeLabel.lineBreakMode = .byTruncatingMiddle

        let agentLabel = NSTextField(labelWithString: rule.agent)
        agentLabel.font = NSFont.systemFont(ofSize: 10)
        agentLabel.textColor = NSColor(white: 1, alpha: 0.3)
        agentLabel.isBordered = false
        agentLabel.drawsBackground = false

        let bodyStack = NSStackView(views: [actionLabel, scopeLabel, agentLabel])
        bodyStack.orientation = .vertical
        bodyStack.alignment = .leading
        bodyStack.spacing = 2
        bodyStack.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(bodyStack)

        // Toggle
        let toggle = NSSwitch()
        toggle.state = rule.enabled ? .on : .off
        toggle.controlSize = .mini
        toggle.translatesAutoresizingMaskIntoConstraints = false
        toggle.target = self
        toggle.action = #selector(ruleToggleChanged(_:))
        toggle.identifier = NSUserInterfaceItemIdentifier(rule.id)
        row.addSubview(toggle)

        // Delete
        let deleteBtn = FirstClickButton(title: "🗑", target: self, action: #selector(deleteRuleTapped(_:)))
        deleteBtn.isBordered = false
        deleteBtn.font = NSFont.systemFont(ofSize: 12)
        deleteBtn.contentTintColor = NSColor(white: 1, alpha: 0.2)
        deleteBtn.translatesAutoresizingMaskIntoConstraints = false
        deleteBtn.identifier = NSUserInterfaceItemIdentifier(rule.id)
        row.addSubview(deleteBtn)

        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(greaterThanOrEqualToConstant: 52),

            dot.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 14),
            dot.topAnchor.constraint(equalTo: row.topAnchor, constant: 16),
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),

            bodyStack.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 8),
            bodyStack.topAnchor.constraint(equalTo: row.topAnchor, constant: 8),
            bodyStack.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -8),
            bodyStack.trailingAnchor.constraint(lessThanOrEqualTo: toggle.leadingAnchor, constant: -8),

            toggle.trailingAnchor.constraint(equalTo: deleteBtn.leadingAnchor, constant: -8),
            toggle.centerYAnchor.constraint(equalTo: row.centerYAnchor),

            deleteBtn.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -14),
            deleteBtn.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            deleteBtn.widthAnchor.constraint(equalToConstant: 24),

            border.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 14),
            border.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -14),
            border.bottomAnchor.constraint(equalTo: row.bottomAnchor),
            border.heightAnchor.constraint(equalToConstant: 0.5),
        ])

        return row
    }

    // MARK: - Rules actions

    @objc private func filterChipTapped(_ sender: NSButton) {
        activeFilter = sender.title
        // Update chip styles
        if let chipRow = sender.superview as? NSStackView {
            for case let chip as NSButton in chipRow.arrangedSubviews {
                styleChip(chip, active: chip.title == activeFilter)
            }
        }
        reloadRules()
    }

    @objc private func ruleToggleChanged(_ sender: NSSwitch) {
        guard let ruleId = sender.identifier?.rawValue else { return }
        rulesStore.updateEnabled(id: ruleId, enabled: sender.state == .on)
        reloadRules()
    }

    @objc private func deleteRuleTapped(_ sender: NSButton) {
        guard let ruleId = sender.identifier?.rawValue else { return }
        rulesStore.removeRule(id: ruleId)
        reloadRules()
    }

    @objc private func removeDisabledTapped() {
        rulesStore.removeDisabled()
        reloadRules()
    }

    @objc private func addRuleTapped() {
        showAddRuleSheet()
    }

    // MARK: - Add rule sheet

    private func showAddRuleSheet() {
        let sheet = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 260),
                            styleMask: [.titled, .closable],
                            backing: .buffered, defer: false)
        sheet.title = "Add Rule"
        sheet.appearance = NSAppearance(named: .darkAqua)
        sheet.backgroundColor = NSColor(red: 20/255, green: 20/255, blue: 20/255, alpha: 1)
        sheet.titlebarAppearsTransparent = true

        let content = NSView(frame: NSRect(x: 0, y: 0, width: 340, height: 260))

        // Agent segmented control
        let agentSeg = NSSegmentedControl(labels: ["claude", "cursor", "openai"], trackingMode: .selectOne, target: nil, action: nil)
        agentSeg.selectedSegment = 0
        agentSeg.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(agentSeg)

        // Action dropdown
        let actionPicker = NSPopUpButton(frame: .zero, pullsDown: false)
        actionPicker.addItems(withTitles: [
            "write_file", "read_file", "create_file", "run_shell", "network_request"
        ])
        actionPicker.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(actionPicker)

        // Scope field
        let scopeField = NSTextField()
        scopeField.placeholderString = "e.g. src/**/*.ts"
        scopeField.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        scopeField.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(scopeField)

        // Workspace field — auto-populated from most recent request
        let workspaceField = NSTextField()
        workspaceField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        workspaceField.translatesAutoresizingMaskIntoConstraints = false
        if let rq = requestQueue, let lastReq = rq.requests.last {
            workspaceField.stringValue = lastReq.workspacePath
        }
        content.addSubview(workspaceField)

        // Labels
        let agentLbl = makeFormLabel("Agent")
        let actionLbl = makeFormLabel("Action")
        let scopeLbl = makeFormLabel("Scope")
        let wsLbl = makeFormLabel("Workspace")
        for lbl in [agentLbl, actionLbl, scopeLbl, wsLbl] {
            content.addSubview(lbl)
        }

        // Buttons
        let cancelBtn = NSButton(title: "Cancel", target: nil, action: nil)
        cancelBtn.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(cancelBtn)

        let saveBtn = NSButton(title: "Save", target: nil, action: nil)
        saveBtn.bezelStyle = .rounded
        saveBtn.keyEquivalent = "\r"
        saveBtn.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(saveBtn)

        NSLayoutConstraint.activate([
            agentLbl.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            agentLbl.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            agentSeg.topAnchor.constraint(equalTo: agentLbl.bottomAnchor, constant: 4),
            agentSeg.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            agentSeg.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),

            actionLbl.topAnchor.constraint(equalTo: agentSeg.bottomAnchor, constant: 12),
            actionLbl.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            actionPicker.topAnchor.constraint(equalTo: actionLbl.bottomAnchor, constant: 4),
            actionPicker.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            actionPicker.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),

            scopeLbl.topAnchor.constraint(equalTo: actionPicker.bottomAnchor, constant: 12),
            scopeLbl.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            scopeField.topAnchor.constraint(equalTo: scopeLbl.bottomAnchor, constant: 4),
            scopeField.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            scopeField.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),

            wsLbl.topAnchor.constraint(equalTo: scopeField.bottomAnchor, constant: 12),
            wsLbl.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            workspaceField.topAnchor.constraint(equalTo: wsLbl.bottomAnchor, constant: 4),
            workspaceField.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            workspaceField.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),

            saveBtn.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
            saveBtn.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            cancelBtn.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
            cancelBtn.trailingAnchor.constraint(equalTo: saveBtn.leadingAnchor, constant: -8),
        ])

        sheet.contentView = content

        cancelBtn.target = self
        cancelBtn.action = #selector(cancelSheet(_:))
        cancelBtn.identifier = NSUserInterfaceItemIdentifier("sheetCancel")

        saveBtn.target = self
        saveBtn.action = #selector(saveSheet(_:))

        // Store references on the sheet for retrieval
        objc_setAssociatedObject(sheet, &AssocKeys.agentSeg, agentSeg, .OBJC_ASSOCIATION_RETAIN)
        objc_setAssociatedObject(sheet, &AssocKeys.actionPicker, actionPicker, .OBJC_ASSOCIATION_RETAIN)
        objc_setAssociatedObject(sheet, &AssocKeys.scopeField, scopeField, .OBJC_ASSOCIATION_RETAIN)
        objc_setAssociatedObject(sheet, &AssocKeys.workspaceField, workspaceField, .OBJC_ASSOCIATION_RETAIN)

        self.beginSheet(sheet, completionHandler: nil)
    }

    @objc private func cancelSheet(_ sender: NSButton) {
        guard let sheet = sender.window as? NSPanel, sheet !== self else { return }
        self.endSheet(sheet)
        sheet.orderOut(nil)
    }

    @objc private func saveSheet(_ sender: NSButton) {
        guard let sheet = sender.window as? NSPanel, sheet !== self else { return }
        guard let agentSeg = objc_getAssociatedObject(sheet, &AssocKeys.agentSeg) as? NSSegmentedControl,
              let actionPicker = objc_getAssociatedObject(sheet, &AssocKeys.actionPicker) as? NSPopUpButton,
              let scopeField = objc_getAssociatedObject(sheet, &AssocKeys.scopeField) as? NSTextField,
              let workspaceField = objc_getAssociatedObject(sheet, &AssocKeys.workspaceField) as? NSTextField
        else { return }

        let agents = ["claude", "cursor", "openai"]
        let agent = agents[agentSeg.selectedSegment]
        let action = actionPicker.titleOfSelectedItem ?? "write_file"
        let scope = scopeField.stringValue.isEmpty ? "**" : scopeField.stringValue
        let workspace = workspaceField.stringValue

        let rule = Rule(
            id: "rule_\(UUID().uuidString.prefix(8))",
            agent: agent,
            action: action,
            scope: scope,
            enabled: true,
            createdAt: Date(),
            workspacePath: workspace
        )
        rulesStore.addRule(rule)

        self.endSheet(sheet)
        sheet.orderOut(nil)
        reloadRules()
    }

    // MARK: =====================
    // MARK: TAB 2 — SETTINGS
    // MARK: =====================

    private var newReqSlider: NSSlider!
    private var allowSlider: NSSlider!
    private var denySlider: NSSlider!

    private func makeSettingsTab() -> NSView {
        let container = NSView()
        container.wantsLayer = true

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false

        let clipView = NSClipView()
        clipView.drawsBackground = false
        clipView.documentView = stack
        scrollView.contentView = clipView

        container.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: clipView.topAnchor),
        ])

        // ---- Sound section ----
        stack.addArrangedSubview(makeSectionHeader("SOUND"))

        let soundToggle = NSSwitch()
        soundToggle.state = AudioEngine.shared.isMuted ? .off : .on
        soundToggle.target = self
        soundToggle.action = #selector(soundToggleChanged(_:))
        stack.addArrangedSubview(makeSettingRow("Sounds enabled", control: soundToggle))

        newReqSlider = makeVolumeSlider(value: AudioEngine.shared.volumeNewRequest)
        newReqSlider.target = self
        newReqSlider.action = #selector(newReqVolumeChanged(_:))
        newReqSlider.isEnabled = !AudioEngine.shared.isMuted
        stack.addArrangedSubview(makeSettingRow("New request volume", control: newReqSlider))

        allowSlider = makeVolumeSlider(value: AudioEngine.shared.volumeAllow)
        allowSlider.target = self
        allowSlider.action = #selector(allowVolumeChanged(_:))
        allowSlider.isEnabled = !AudioEngine.shared.isMuted
        stack.addArrangedSubview(makeSettingRow("Allow volume", control: allowSlider))

        denySlider = makeVolumeSlider(value: AudioEngine.shared.volumeDeny)
        denySlider.target = self
        denySlider.action = #selector(denyVolumeChanged(_:))
        denySlider.isEnabled = !AudioEngine.shared.isMuted
        stack.addArrangedSubview(makeSettingRow("Deny volume", control: denySlider))

        // ---- Behaviour section ----
        stack.addArrangedSubview(makeSectionHeader("BEHAVIOUR"))

        let hotkeyRow = makeHotkeyRow()
        stack.addArrangedSubview(hotkeyRow)

        let autoCloseToggle = NSSwitch()
        autoCloseToggle.state = UserDefaults.standard.object(forKey: "autoCloseTray") == nil
            ? .on : (UserDefaults.standard.bool(forKey: "autoCloseTray") ? .on : .off)
        autoCloseToggle.target = self
        autoCloseToggle.action = #selector(autoCloseChanged(_:))
        stack.addArrangedSubview(makeSettingRow("Auto-close tray after action", control: autoCloseToggle))

        let loginToggle = NSSwitch()
        if #available(macOS 13.0, *) {
            loginToggle.state = SMAppService.mainApp.status == .enabled ? .on : .off
        }
        loginToggle.target = self
        loginToggle.action = #selector(loginToggleChanged(_:))
        stack.addArrangedSubview(makeSettingRow("Launch at login", control: loginToggle))

        // ---- About section ----
        stack.addArrangedSubview(makeSectionHeader("ABOUT"))

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let versionLabel = NSTextField(labelWithString: "Agent Vibe Island v\(version)")
        versionLabel.font = NSFont.systemFont(ofSize: 11)
        versionLabel.textColor = NSColor(white: 1, alpha: 0.5)
        versionLabel.isBordered = false
        versionLabel.drawsBackground = false
        versionLabel.translatesAutoresizingMaskIntoConstraints = false

        let githubBtn = makeSmallButton(title: "GitHub ↗")
        githubBtn.target = self
        githubBtn.action = #selector(openGitHub)

        let aboutRow = NSStackView(views: [versionLabel, githubBtn])
        aboutRow.orientation = .horizontal
        aboutRow.translatesAutoresizingMaskIntoConstraints = false
        let aboutWrapper = wrapWithPadding(aboutRow)
        stack.addArrangedSubview(aboutWrapper)
        aboutWrapper.leadingAnchor.constraint(equalTo: stack.leadingAnchor).isActive = true
        aboutWrapper.trailingAnchor.constraint(equalTo: stack.trailingAnchor).isActive = true

        return container
    }

    // MARK: - Settings actions

    @objc private func soundToggleChanged(_ sender: NSSwitch) {
        AudioEngine.shared.isMuted = (sender.state == .off)
        newReqSlider.isEnabled = sender.state == .on
        allowSlider.isEnabled = sender.state == .on
        denySlider.isEnabled = sender.state == .on
    }

    @objc private func newReqVolumeChanged(_ sender: NSSlider) {
        AudioEngine.shared.volumeNewRequest = sender.floatValue
    }

    @objc private func allowVolumeChanged(_ sender: NSSlider) {
        AudioEngine.shared.volumeAllow = sender.floatValue
    }

    @objc private func denyVolumeChanged(_ sender: NSSlider) {
        AudioEngine.shared.volumeDeny = sender.floatValue
    }

    @objc private func autoCloseChanged(_ sender: NSSwitch) {
        UserDefaults.standard.set(sender.state == .on, forKey: "autoCloseTray")
    }

    @objc private func loginToggleChanged(_ sender: NSSwitch) {
        if #available(macOS 13.0, *) {
            do {
                if sender.state == .on {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                NSLog("AgentVibeIsland: Login item toggle failed: %@", error.localizedDescription)
                // Revert UI
                sender.state = sender.state == .on ? .off : .on
            }
        }
    }

    @objc private func openGitHub() {
        if let url = URL(string: "https://github.com/clarkyao_microsoft/AgentVibeIsland") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Hotkey row

    private var hotkeyLabel: NSTextField!
    private var hotkeyChangeBtn: NSButton!
    private var isRecordingHotkey = false
    private var hotkeyMonitor: Any?

    private func makeHotkeyRow() -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: "Open tray hotkey")
        label.font = NSFont.systemFont(ofSize: 11)
        label.textColor = NSColor(white: 1, alpha: 0.75)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isBordered = false
        label.drawsBackground = false
        row.addSubview(label)

        hotkeyLabel = NSTextField(labelWithString: currentHotkeyString())
        hotkeyLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        hotkeyLabel.textColor = NSColor(white: 1, alpha: 0.5)
        hotkeyLabel.translatesAutoresizingMaskIntoConstraints = false
        hotkeyLabel.isBordered = false
        hotkeyLabel.drawsBackground = false
        row.addSubview(hotkeyLabel)

        hotkeyChangeBtn = makeSmallButton(title: "Change")
        hotkeyChangeBtn.target = self
        hotkeyChangeBtn.action = #selector(changeHotkeyTapped)
        row.addSubview(hotkeyChangeBtn)

        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 32),
            label.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 14),
            label.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            hotkeyChangeBtn.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -14),
            hotkeyChangeBtn.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            hotkeyLabel.trailingAnchor.constraint(equalTo: hotkeyChangeBtn.leadingAnchor, constant: -8),
            hotkeyLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),
        ])
        return row
    }

    @objc private func changeHotkeyTapped() {
        if isRecordingHotkey {
            stopRecordingHotkey()
            return
        }
        isRecordingHotkey = true
        hotkeyLabel.stringValue = "Press new shortcut…"
        hotkeyChangeBtn.title = "Cancel"

        hotkeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard !mods.isEmpty else { return event }

            UserDefaults.standard.set(Int(mods.rawValue), forKey: "trayHotkeyModifiers")
            UserDefaults.standard.set(Int(event.keyCode), forKey: "trayHotkeyKeyCode")

            self.hotkeyLabel.stringValue = self.currentHotkeyString()
            self.stopRecordingHotkey()
            self.onHotkeyChanged?(mods, event.keyCode)
            return nil // consume the event
        }
    }

    private func stopRecordingHotkey() {
        isRecordingHotkey = false
        hotkeyChangeBtn.title = "Change"
        if let monitor = hotkeyMonitor {
            NSEvent.removeMonitor(monitor)
            hotkeyMonitor = nil
        }
    }

    private func currentHotkeyString() -> String {
        let modRaw = UserDefaults.standard.integer(forKey: "trayHotkeyModifiers")
        let keyCode = UserDefaults.standard.integer(forKey: "trayHotkeyKeyCode")

        if modRaw == 0 && keyCode == 0 {
            return "⌥Space"
        }

        let mods = NSEvent.ModifierFlags(rawValue: UInt(modRaw))
        var parts: [String] = []
        if mods.contains(.control) { parts.append("⌃") }
        if mods.contains(.option) { parts.append("⌥") }
        if mods.contains(.shift) { parts.append("⇧") }
        if mods.contains(.command) { parts.append("⌘") }
        parts.append(keyCodeToString(UInt16(keyCode)))
        return parts.joined()
    }

    private func keyCodeToString(_ code: UInt16) -> String {
        switch code {
        case 49: return "Space"
        case 36: return "Return"
        case 53: return "Esc"
        case 48: return "Tab"
        default:
            // Use Carbon key mapping
            let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
            guard let layoutDataRef = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
                return "Key\(code)"
            }
            let layoutData = unsafeBitCast(layoutDataRef, to: CFData.self)
            let layoutPtr = CFDataGetBytePtr(layoutData)!
            var deadKeyState: UInt32 = 0
            var chars = [UniChar](repeating: 0, count: 4)
            var length: Int = 0
            let _ = UCKeyTranslate(
                layoutPtr.withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { $0 },
                code, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                UInt32(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState, chars.count, &length, &chars
            )
            if length > 0 {
                return String(utf16CodeUnits: chars, count: length).uppercased()
            }
            return "Key\(code)"
        }
    }

    // MARK: =====================
    // MARK: HELPERS
    // MARK: =====================

    private func makeSectionHeader(_ text: String) -> NSView {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        label.textColor = NSColor(white: 1, alpha: 0.28)
        label.isBordered = false
        label.drawsBackground = false
        if let attrStr = label.attributedStringValue.mutableCopy() as? NSMutableAttributedString {
            attrStr.addAttribute(.kern, value: 0.6,
                                 range: NSRange(location: 0, length: attrStr.length))
            label.attributedStringValue = attrStr
        }
        label.translatesAutoresizingMaskIntoConstraints = false
        let wrapper = NSView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 14),
            label.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 12),
            label.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -4),
        ])
        return wrapper
    }

    private func makeSettingRow(_ title: String, control: NSView) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: title)
        label.font = NSFont.systemFont(ofSize: 11)
        label.textColor = NSColor(white: 1, alpha: 0.75)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isBordered = false
        label.drawsBackground = false
        row.addSubview(label)

        control.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(control)

        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 32),
            label.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 14),
            label.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            control.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -14),
            control.centerYAnchor.constraint(equalTo: row.centerYAnchor),
        ])
        return row
    }

    private func wrapWithPadding(_ view: NSView) -> NSView {
        let wrapper = NSView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        view.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 14),
            view.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -14),
            view.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 4),
            view.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -4),
        ])
        return wrapper
    }

    private func makeSmallButton(title: String) -> NSButton {
        let btn = FirstClickButton(title: title, target: nil, action: nil)
        btn.isBordered = false
        btn.wantsLayer = true
        btn.layer?.backgroundColor = NSColor(white: 1, alpha: 0.07).cgColor
        btn.layer?.borderWidth = 0.5
        btn.layer?.borderColor = NSColor(white: 1, alpha: 0.14).cgColor
        btn.layer?.cornerRadius = 6
        btn.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        btn.contentTintColor = NSColor(white: 1, alpha: 0.6)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.heightAnchor.constraint(equalToConstant: 22).isActive = true
        btn.widthAnchor.constraint(greaterThanOrEqualToConstant: 60).isActive = true
        return btn
    }

    private func makeChipButton(title: String, active: Bool) -> NSButton {
        let btn = FirstClickButton(title: title, target: nil, action: nil)
        btn.isBordered = false
        btn.wantsLayer = true
        btn.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.heightAnchor.constraint(equalToConstant: 22).isActive = true
        styleChip(btn, active: active)
        return btn
    }

    private func styleChip(_ btn: NSButton, active: Bool) {
        if active {
            btn.layer?.backgroundColor = NSColor(white: 1, alpha: 0.10).cgColor
            btn.layer?.borderWidth = 0.5
            btn.layer?.borderColor = NSColor(white: 1, alpha: 0.15).cgColor
            btn.contentTintColor = NSColor(white: 1, alpha: 0.85)
        } else {
            btn.layer?.backgroundColor = NSColor.clear.cgColor
            btn.layer?.borderWidth = 0
            btn.contentTintColor = NSColor(white: 1, alpha: 0.4)
        }
        btn.layer?.cornerRadius = 6
    }

    private func makeVolumeSlider(value: Float) -> NSSlider {
        let slider = NSSlider(value: Double(value), minValue: 0, maxValue: 100,
                              target: nil, action: nil)
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.widthAnchor.constraint(equalToConstant: 140).isActive = true
        return slider
    }

    private func makeFormLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        label.textColor = NSColor(white: 1, alpha: 0.5)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isBordered = false
        label.drawsBackground = false
        return label
    }

    private func agentColor(for agent: String) -> NSColor {
        switch agent.lowercased() {
        case "claude": return NSColor(red: 192/255, green: 132/255, blue: 252/255, alpha: 1) // #c084fc
        case "cursor": return NSColor(red: 96/255, green: 165/255, blue: 250/255, alpha: 1)  // #60a5fa
        case "openai": return NSColor(red: 74/255, green: 222/255, blue: 128/255, alpha: 1)   // #4ade80
        default:       return NSColor(white: 1, alpha: 0.4)
        }
    }

    private func actionDisplayName(_ action: String) -> String {
        switch action {
        case "write_file": return "Write to file"
        case "read_file": return "Read file"
        case "create_file": return "Create file"
        case "run_shell": return "Run shell command"
        case "network_request": return "Network request"
        default: return action
        }
    }
}

// Associated object keys for sheet controls
private struct AssocKeys {
    static var agentSeg = 0
    static var actionPicker = 0
    static var scopeField = 0
    static var workspaceField = 0
}
