import AppKit

/// Permission card shown inside an agent row for a pending request.
final class PermissionCardView: NSView {

    private let request: PermissionRequest
    private weak var requestQueue: RequestQueue?
    private weak var rulesStore: RulesStore?
    private let requestReceivedAt = Date()
    private var snoozeTimer: Timer?
    private var waitingTimer: Timer?
    private let waitingLabel = NSTextField(labelWithString: "")

    var onResolved: (() -> Void)?

    // MARK: - Init

    init(request: PermissionRequest, requestQueue: RequestQueue, rulesStore: RulesStore) {
        self.request = request
        self.requestQueue = requestQueue
        self.rulesStore = rulesStore
        super.init(frame: .zero)
        wantsLayer = true
        setupLayout()
        startWaitingTimer()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    deinit {
        snoozeTimer?.invalidate()
        waitingTimer?.invalidate()
    }

    // MARK: - Layout

    private func setupLayout() {
        layer?.backgroundColor = NSColor(white: 1, alpha: 0.03).cgColor
        layer?.cornerRadius = 8
        translatesAutoresizingMaskIntoConstraints = false

        let cardStack = NSStackView()
        cardStack.orientation = .vertical
        cardStack.alignment = .leading
        cardStack.spacing = 6
        cardStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(cardStack)

        // Row 1: action icon + label
        let actionRow = NSStackView()
        actionRow.orientation = .horizontal
        actionRow.spacing = 4

        let actionIcon = NSTextField(labelWithString: "⚡")
        actionIcon.font = NSFont.systemFont(ofSize: 11)
        actionIcon.textColor = NSColor(red: 251/255, green: 191/255, blue: 36/255, alpha: 1)
        actionIcon.isBordered = false
        actionIcon.drawsBackground = false

        let actionLabel = NSTextField(labelWithString: request.actionLabel)
        actionLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        actionLabel.textColor = NSColor(white: 1, alpha: 0.75)
        actionLabel.isBordered = false
        actionLabel.drawsBackground = false

        actionRow.addArrangedSubview(actionIcon)
        actionRow.addArrangedSubview(actionLabel)
        cardStack.addArrangedSubview(actionRow)

        // Row 2: scope path
        let scopeLabel = NSTextField(labelWithString: request.scope)
        scopeLabel.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        scopeLabel.textColor = NSColor(white: 1, alpha: 0.35)
        scopeLabel.wantsLayer = true
        scopeLabel.layer?.backgroundColor = NSColor(white: 1, alpha: 0.05).cgColor
        scopeLabel.layer?.cornerRadius = 4
        scopeLabel.isBordered = false
        scopeLabel.drawsBackground = false
        scopeLabel.lineBreakMode = .byTruncatingMiddle
        cardStack.addArrangedSubview(scopeLabel)

        // Waiting label (hidden initially, shown after 5 min)
        waitingLabel.font = NSFont.systemFont(ofSize: 9)
        waitingLabel.textColor = NSColor(white: 1, alpha: 0.25)
        waitingLabel.isBordered = false
        waitingLabel.drawsBackground = false
        waitingLabel.isHidden = true
        cardStack.addArrangedSubview(waitingLabel)

        // Row 3: buttons
        let buttonRow = NSStackView()
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 6
        buttonRow.distribution = .fill

        let allowBtn = makeButton(
            title: "Allow",
            bgColor: NSColor(red: 187/255, green: 247/255, blue: 208/255, alpha: 1),
            textColor: NSColor(red: 20/255, green: 83/255, blue: 45/255, alpha: 1)
        )
        allowBtn.target = self
        allowBtn.action = #selector(allowTapped)

        let denyBtn = makeButton(
            title: "Deny",
            bgColor: NSColor(red: 254/255, green: 202/255, blue: 202/255, alpha: 1),
            textColor: NSColor(red: 127/255, green: 29/255, blue: 29/255, alpha: 1)
        )
        denyBtn.target = self
        denyBtn.action = #selector(denyTapped)

        let snoozeBtn = makeButton(
            title: "Snooze",
            bgColor: NSColor(white: 1, alpha: 0.08),
            textColor: NSColor(white: 1, alpha: 0.55)
        )
        snoozeBtn.target = self
        snoozeBtn.action = #selector(snoozeTapped)

        buttonRow.addArrangedSubview(allowBtn)
        buttonRow.addArrangedSubview(denyBtn)
        buttonRow.addArrangedSubview(snoozeBtn)
        cardStack.addArrangedSubview(buttonRow)

        // "Always allow" link
        let alwaysAllow = FirstClickButton(title: "always allow", target: self, action: #selector(alwaysAllowTapped))
        alwaysAllow.isBordered = false
        alwaysAllow.font = NSFont.systemFont(ofSize: 10)
        alwaysAllow.contentTintColor = NSColor(white: 1, alpha: 0.25)
        let attrTitle = NSMutableAttributedString(string: "always allow")
        attrTitle.addAttributes([
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .foregroundColor: NSColor(white: 1, alpha: 0.25),
            .font: NSFont.systemFont(ofSize: 10),
        ], range: NSRange(location: 0, length: attrTitle.length))
        alwaysAllow.attributedTitle = attrTitle
        alwaysAllow.translatesAutoresizingMaskIntoConstraints = false
        cardStack.addArrangedSubview(alwaysAllow)
        // Right-align the always allow link
        if let sv = alwaysAllow.superview {
            alwaysAllow.trailingAnchor.constraint(equalTo: sv.trailingAnchor).isActive = true
        }

        // Card stack constraints
        NSLayoutConstraint.activate([
            cardStack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            cardStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            cardStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            cardStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])
    }

    // MARK: - Button factory

    private func makeButton(title: String, bgColor: NSColor, textColor: NSColor) -> NSButton {
        let btn = FirstClickButton(title: title, target: nil, action: nil)
        btn.isBordered = false
        btn.wantsLayer = true
        btn.layer?.backgroundColor = bgColor.cgColor
        btn.layer?.cornerRadius = 5
        btn.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        btn.contentTintColor = textColor

        let attrTitle = NSAttributedString(string: title, attributes: [
            .foregroundColor: textColor,
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
        ])
        btn.attributedTitle = attrTitle
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.heightAnchor.constraint(equalToConstant: 24).isActive = true
        btn.widthAnchor.constraint(greaterThanOrEqualToConstant: 52).isActive = true
        return btn
    }

    // MARK: - Actions

    @objc private func allowTapped() {
        resolve(decision: "allow")
    }

    @objc private func denyTapped() {
        resolve(decision: "deny")
    }

    @objc private func snoozeTapped() {
        // Hide the card visually
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            ctx.allowsImplicitAnimation = true
            self.alphaValue = 0
        }, completionHandler: {
            self.isHidden = true
        })

        // Re-surface after 5 minutes
        snoozeTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.isHidden = false
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.2
                    self?.alphaValue = 1
                }
                // Notify to re-pulse
                self?.onResolved?()
            }
        }
    }

    @objc private func alwaysAllowTapped() {
        // Create rule
        let rule = Rule(
            id: "rule_\(UUID().uuidString.prefix(8))",
            agent: request.agent,
            action: request.action,
            scope: scopeToGlob(request.scope),
            enabled: true,
            createdAt: Date(),
            workspacePath: request.workspacePath
        )
        rulesStore?.addRule(rule)
        resolve(decision: "allow")
    }

    private func resolve(decision: String) {
        snoozeTimer?.invalidate()
        waitingTimer?.invalidate()

        if decision == "allow" {
            AudioEngine.shared.playAllow()
        } else if decision == "deny" {
            AudioEngine.shared.playDeny()
        }

        let pd = PermissionDecision(requestId: request.requestId, decision: decision)
        requestQueue?.resolve(requestId: request.requestId, decision: pd)

        // Animate out
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            ctx.allowsImplicitAnimation = true
            self.alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.isHidden = true
            self?.onResolved?()
        })
    }

    /// Convert a specific file path into a directory glob pattern for rule creation.
    private func scopeToGlob(_ scope: String) -> String {
        let components = scope.split(separator: "/")
        if components.count > 1 {
            let dir = components.dropLast().joined(separator: "/")
            return dir + "/**"
        }
        return "**"
    }

    // MARK: - Waiting timer

    private func startWaitingTimer() {
        waitingTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateWaitingLabel()
            }
        }
    }

    private func updateWaitingLabel() {
        let elapsed = Date().timeIntervalSince(requestReceivedAt)
        let minutes = Int(elapsed / 60)
        if minutes >= 5 {
            waitingLabel.isHidden = false
            waitingLabel.stringValue = "waiting \(minutes)m"
        }
    }
}
