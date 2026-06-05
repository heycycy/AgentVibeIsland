import AppKit

/// Displays a single agent's status, progress, and any pending permission cards.
final class AgentRowView: NSView {

    private let agent: Agent
    private let status: StatusUpdate?
    private let pendingRequests: [PermissionRequest]
    private weak var requestQueue: RequestQueue?
    private weak var rulesStore: RulesStore?

    var onRequestResolved: (() -> Void)?

    // MARK: - Agent theme colors

    private struct AgentTheme {
        let iconBg: NSColor
        let iconTint: NSColor
        let progressFill: NSColor
        let initial: String
    }

    private static func theme(for agentName: String) -> AgentTheme {
        switch agentName.lowercased() {
        case "claude":
            return AgentTheme(
                iconBg: NSColor(red: 45/255, green: 31/255, blue: 64/255, alpha: 1),
                iconTint: NSColor(red: 192/255, green: 132/255, blue: 252/255, alpha: 1),
                progressFill: NSColor(red: 168/255, green: 85/255, blue: 247/255, alpha: 1),
                initial: "C"
            )
        case "cursor":
            return AgentTheme(
                iconBg: NSColor(red: 26/255, green: 37/255, blue: 64/255, alpha: 1),
                iconTint: NSColor(red: 96/255, green: 165/255, blue: 250/255, alpha: 1),
                progressFill: NSColor(red: 59/255, green: 130/255, blue: 246/255, alpha: 1),
                initial: "Cu"
            )
        case "codex", "openai":
            return AgentTheme(
                iconBg: NSColor(red: 15/255, green: 38/255, blue: 24/255, alpha: 1),
                iconTint: NSColor(red: 74/255, green: 222/255, blue: 128/255, alpha: 1),
                progressFill: NSColor(red: 74/255, green: 222/255, blue: 128/255, alpha: 1),
                initial: "O"
            )
        default:
            return AgentTheme(
                iconBg: NSColor(white: 0.15, alpha: 1),
                iconTint: NSColor(white: 0.6, alpha: 1),
                progressFill: NSColor(white: 0.4, alpha: 1),
                initial: String(agentName.prefix(1)).uppercased()
            )
        }
    }

    // MARK: - Init

    init(agent: Agent, status: StatusUpdate?, pendingRequests: [PermissionRequest],
         requestQueue: RequestQueue, rulesStore: RulesStore) {
        self.agent = agent
        self.status = status
        self.pendingRequests = pendingRequests
        self.requestQueue = requestQueue
        self.rulesStore = rulesStore
        super.init(frame: .zero)
        wantsLayer = true
        setupLayout()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Layout

    private func setupLayout() {
        translatesAutoresizingMaskIntoConstraints = false
        let theme = AgentRowView.theme(for: agent.agent)

        // Agent icon
        let iconView = NSView()
        iconView.wantsLayer = true
        iconView.layer?.backgroundColor = theme.iconBg.cgColor
        iconView.layer?.cornerRadius = 7
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let iconLabel = NSTextField(labelWithString: theme.initial)
        iconLabel.font = NSFont.systemFont(ofSize: 12, weight: .bold)
        iconLabel.textColor = theme.iconTint
        iconLabel.alignment = .center
        iconLabel.translatesAutoresizingMaskIntoConstraints = false
        iconLabel.isBordered = false
        iconLabel.drawsBackground = false
        iconView.addSubview(iconLabel)

        addSubview(iconView)

        // Body column
        let bodyStack = NSStackView()
        bodyStack.orientation = .vertical
        bodyStack.alignment = .leading
        bodyStack.spacing = 3
        bodyStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bodyStack)

        // Row 1: agent name + status badge
        let nameRow = NSStackView()
        nameRow.orientation = .horizontal
        nameRow.spacing = 6

        let nameLabel = NSTextField(labelWithString: agent.agentLabel)
        nameLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        nameLabel.textColor = NSColor(white: 1, alpha: 0.85)
        nameLabel.isBordered = false
        nameLabel.drawsBackground = false

        let badgeText: String
        let badgeBgColor: NSColor
        let badgeTextColor: NSColor
        if !pendingRequests.isEmpty {
            badgeText = "waiting"
            badgeBgColor = NSColor(red: 251/255, green: 191/255, blue: 36/255, alpha: 0.15)
            badgeTextColor = NSColor(red: 251/255, green: 191/255, blue: 36/255, alpha: 1)
        } else {
            badgeText = "running"
            badgeBgColor = NSColor(red: 74/255, green: 222/255, blue: 128/255, alpha: 0.12)
            badgeTextColor = NSColor(red: 74/255, green: 222/255, blue: 128/255, alpha: 1)
        }

        let badge = NSTextField(labelWithString: badgeText)
        badge.font = NSFont.systemFont(ofSize: 9, weight: .medium)
        badge.textColor = badgeTextColor
        badge.wantsLayer = true
        badge.layer?.backgroundColor = badgeBgColor.cgColor
        badge.layer?.cornerRadius = 3
        badge.isBordered = false
        badge.drawsBackground = false

        nameRow.addArrangedSubview(nameLabel)
        nameRow.addArrangedSubview(badge)
        bodyStack.addArrangedSubview(nameRow)

        // Row 2: task description
        let taskDesc = status?.taskDescription ?? pendingRequests.first?.taskDescription ?? ""
        if !taskDesc.isEmpty {
            let taskLabel = NSTextField(labelWithString: taskDesc)
            taskLabel.font = NSFont.systemFont(ofSize: 10)
            taskLabel.textColor = NSColor(white: 1, alpha: 0.45)
            taskLabel.lineBreakMode = .byTruncatingTail
            taskLabel.isBordered = false
            taskLabel.drawsBackground = false
            bodyStack.addArrangedSubview(taskLabel)
        }

        // Row 3: progress bar
        let progress = status?.taskProgress ?? pendingRequests.first?.taskProgress
        if let prog = progress {
            let progressBg = NSView()
            progressBg.wantsLayer = true
            progressBg.layer?.backgroundColor = NSColor(white: 1, alpha: 0.08).cgColor
            progressBg.layer?.cornerRadius = 1
            progressBg.translatesAutoresizingMaskIntoConstraints = false

            let progressFill = NSView()
            progressFill.wantsLayer = true
            progressFill.layer?.backgroundColor = theme.progressFill.cgColor
            progressFill.layer?.cornerRadius = 1
            progressFill.translatesAutoresizingMaskIntoConstraints = false
            progressBg.addSubview(progressFill)

            bodyStack.addArrangedSubview(progressBg)

            NSLayoutConstraint.activate([
                progressBg.heightAnchor.constraint(equalToConstant: 2),
                progressBg.widthAnchor.constraint(equalToConstant: 280),
                progressFill.topAnchor.constraint(equalTo: progressBg.topAnchor),
                progressFill.bottomAnchor.constraint(equalTo: progressBg.bottomAnchor),
                progressFill.leadingAnchor.constraint(equalTo: progressBg.leadingAnchor),
                progressFill.widthAnchor.constraint(equalTo: progressBg.widthAnchor,
                                                     multiplier: CGFloat(min(max(prog, 0), 1))),
            ])
        }

        // Row 4+: permission cards
        for req in pendingRequests {
            let card = PermissionCardView(request: req, requestQueue: requestQueue!, rulesStore: rulesStore!)
            card.onResolved = { [weak self] in
                self?.onRequestResolved?()
            }
            bodyStack.addArrangedSubview(card)
            card.widthAnchor.constraint(equalToConstant: 300).isActive = true
        }

        // Constraints
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            iconView.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            iconView.widthAnchor.constraint(equalToConstant: 26),
            iconView.heightAnchor.constraint(equalToConstant: 26),

            iconLabel.centerXAnchor.constraint(equalTo: iconView.centerXAnchor),
            iconLabel.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),

            bodyStack.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            bodyStack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            bodyStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            bodyStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])
    }
}
