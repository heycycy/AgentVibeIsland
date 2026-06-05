import AppKit

/// Dropdown tray that appears below the notch wings, showing agent rows and permission cards.
final class TrayView: NSView {

    private weak var requestQueue: RequestQueue?
    private weak var agentRegistry: AgentRegistry?
    private weak var rulesStore: RulesStore?

    private let stackView = NSStackView()
    private let pendingSectionLabel = NSTextField(labelWithString: "")
    private let runningSectionLabel = NSTextField(labelWithString: "")
    private let footerView = NSView()

    var onRequestResolved: (() -> Void)?
    var onPreferencesTapped: (() -> Void)?

    // MARK: - Init

    init(requestQueue: RequestQueue, agentRegistry: AgentRegistry, rulesStore: RulesStore) {
        self.requestQueue = requestQueue
        self.agentRegistry = agentRegistry
        self.rulesStore = rulesStore
        super.init(frame: .zero)
        wantsLayer = true
        setupAppearance()
        setupLayout()
        reload()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Appearance

    private func setupAppearance() {
        layer?.backgroundColor = NSColor(red: 20/255, green: 20/255, blue: 20/255, alpha: 1).cgColor
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor(white: 1, alpha: 0.10).cgColor
        layer?.cornerRadius = 18
        layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        // Bottom corners only — but AppKit Y is flipped relative to CALayer
        // layerMinXMinYCorner = bottom-left in layer coords = bottom-left visually
        layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]

        // Remove top border by overlaying a thin view
        let topMask = NSView()
        topMask.wantsLayer = true
        topMask.layer?.backgroundColor = NSColor(red: 20/255, green: 20/255, blue: 20/255, alpha: 1).cgColor
        topMask.translatesAutoresizingMaskIntoConstraints = false
        addSubview(topMask)
        NSLayoutConstraint.activate([
            topMask.topAnchor.constraint(equalTo: topAnchor),
            topMask.leadingAnchor.constraint(equalTo: leadingAnchor),
            topMask.trailingAnchor.constraint(equalTo: trailingAnchor),
            topMask.heightAnchor.constraint(equalToConstant: 1),
        ])
    }

    private func setupLayout() {
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 0
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        // Footer
        setupFooter()
    }

    private func setupFooter() {
        footerView.wantsLayer = true
        footerView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(footerView)

        let sep = NSView()
        sep.wantsLayer = true
        sep.layer?.backgroundColor = NSColor(white: 1, alpha: 0.07).cgColor
        sep.translatesAutoresizingMaskIntoConstraints = false
        footerView.addSubview(sep)

        let historyBtn = FirstClickButton(title: "History", target: self, action: #selector(historyTapped))
        historyBtn.font = NSFont.systemFont(ofSize: 10)
        historyBtn.contentTintColor = NSColor(white: 1, alpha: 0.28)
        historyBtn.translatesAutoresizingMaskIntoConstraints = false
        historyBtn.isBordered = false
        footerView.addSubview(historyBtn)

        let prefsBtn = FirstClickButton(title: "Preferences", target: self, action: #selector(prefsTapped))
        prefsBtn.font = NSFont.systemFont(ofSize: 10)
        prefsBtn.contentTintColor = NSColor(white: 1, alpha: 0.28)
        prefsBtn.translatesAutoresizingMaskIntoConstraints = false
        prefsBtn.isBordered = false
        footerView.addSubview(prefsBtn)

        NSLayoutConstraint.activate([
            footerView.topAnchor.constraint(equalTo: stackView.bottomAnchor, constant: 4),
            footerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            footerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            footerView.bottomAnchor.constraint(equalTo: bottomAnchor),
            footerView.heightAnchor.constraint(equalToConstant: 28),

            sep.topAnchor.constraint(equalTo: footerView.topAnchor),
            sep.leadingAnchor.constraint(equalTo: footerView.leadingAnchor, constant: 14),
            sep.trailingAnchor.constraint(equalTo: footerView.trailingAnchor, constant: -14),
            sep.heightAnchor.constraint(equalToConstant: 0.5),

            historyBtn.leadingAnchor.constraint(equalTo: footerView.leadingAnchor, constant: 14),
            historyBtn.centerYAnchor.constraint(equalTo: footerView.centerYAnchor),

            prefsBtn.trailingAnchor.constraint(equalTo: footerView.trailingAnchor, constant: -14),
            prefsBtn.centerYAnchor.constraint(equalTo: footerView.centerYAnchor),
        ])
    }

    // MARK: - Reload

    func reload() {
        guard let rq = requestQueue, let ar = agentRegistry, let rs = rulesStore else { return }

        // Clear old content
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let allStates = ar.allStates
        let pending = rq.requests

        // Group agents by pending status
        let agentsWithPending = allStates.filter { state in
            pending.contains { $0.agent == state.agent.agent }
        }
        let agentsRunning = allStates.filter { state in
            !pending.contains { $0.agent == state.agent.agent }
        }

        // Pending section
        if !agentsWithPending.isEmpty {
            let label = makeSectionLabel("PENDING · \(agentsWithPending.count)")
            stackView.addArrangedSubview(label)
            label.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true

            for state in agentsWithPending {
                let agentPending = pending.filter { $0.agent == state.agent.agent }
                let row = AgentRowView(agent: state.agent, status: state.status,
                                       pendingRequests: agentPending,
                                       requestQueue: rq, rulesStore: rs)
                row.onRequestResolved = { [weak self] in
                    self?.onRequestResolved?()
                    self?.reload()
                }
                stackView.addArrangedSubview(row)
                row.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true
            }
        }

        // Running section
        if !agentsRunning.isEmpty {
            let label = makeSectionLabel("RUNNING · \(agentsRunning.count)")
            stackView.addArrangedSubview(label)
            label.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true

            for state in agentsRunning {
                let row = AgentRowView(agent: state.agent, status: state.status,
                                       pendingRequests: [],
                                       requestQueue: rq, rulesStore: rs)
                stackView.addArrangedSubview(row)
                row.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true
            }
        }

        // If no agents
        if allStates.isEmpty {
            let empty = NSTextField(labelWithString: "No agents connected")
            empty.font = NSFont.systemFont(ofSize: 11)
            empty.textColor = NSColor(white: 1, alpha: 0.3)
            empty.alignment = .center
            empty.translatesAutoresizingMaskIntoConstraints = false
            empty.isBordered = false
            empty.drawsBackground = false
            let wrapper = NSView()
            wrapper.translatesAutoresizingMaskIntoConstraints = false
            wrapper.addSubview(empty)
            NSLayoutConstraint.activate([
                empty.centerXAnchor.constraint(equalTo: wrapper.centerXAnchor),
                empty.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 16),
                empty.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -16),
            ])
            stackView.addArrangedSubview(wrapper)
            wrapper.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true
        }

        invalidateIntrinsicContentSize()
    }

    // MARK: - Intrinsic Size

    override var intrinsicContentSize: NSSize {
        let stackHeight = stackView.fittingSize.height + 8 // top padding
        return NSSize(width: NSView.noIntrinsicMetric, height: stackHeight + 28) // + footer
    }

    // MARK: - Helpers

    private func makeSectionLabel(_ text: String) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        label.textColor = NSColor(white: 1, alpha: 0.28)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isBordered = false
        label.drawsBackground = false

        // Apply tracking (letter-spacing)
        if let attrStr = label.attributedStringValue.mutableCopy() as? NSMutableAttributedString {
            attrStr.addAttribute(.kern, value: 0.6,
                                 range: NSRange(location: 0, length: attrStr.length))
            label.attributedStringValue = attrStr
        }

        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4),
        ])
        container.heightAnchor.constraint(greaterThanOrEqualToConstant: 22).isActive = true
        return container
    }

    // MARK: - Footer actions

    @objc private func historyTapped() {
        let alert = NSAlert()
        alert.messageText = "History"
        alert.informativeText = "History coming in a future update."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func prefsTapped() {
        if let callback = onPreferencesTapped {
            callback()
        } else {
            RulesManagerWindow.show(rulesStore: rulesStore!, agentRegistry: agentRegistry, requestQueue: requestQueue)
        }
    }
}
