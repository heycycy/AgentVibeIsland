import AppKit

/// A wing that extends from one side of the physical notch.
final class WingView: NSView {

    enum Side { case left, right }
    enum DotState { case running, waiting, idle }

    private let side: Side

    // Subviews
    private let backgroundLayer = CALayer()
    private var dotLayers: [CALayer] = []
    private let badgeLabel = NSTextField(labelWithString: "")
    private let badgeBg = NSView()
    private let agentsLabel = NSTextField(labelWithString: "agents")
    private let separatorView = NSView()
    private let chevronLabel = NSTextField(labelWithString: "▾")

    private let contentContainer = NSView()

    // MARK: - Init

    init(side: Side) {
        self.side = side
        super.init(frame: .zero)
        wantsLayer = true
        setupLayers()
        setupContent()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    var contentAlpha: CGFloat {
        get { contentContainer.alphaValue }
        set { contentContainer.alphaValue = newValue }
    }

    // MARK: - Setup

    private func setupLayers() {
        let bg = CALayer()
        bg.backgroundColor = NSColor.black.cgColor

        if side == .left {
            bg.maskedCorners = [.layerMinXMinYCorner] // bottom-left
        } else {
            bg.maskedCorners = [.layerMaxXMinYCorner] // bottom-right
        }
        bg.cornerRadius = 16
        layer?.addSublayer(bg)
        backgroundLayer.removeFromSuperlayer()
        layer?.insertSublayer(bg, at: 0)

        // Keep reference
        _ = { self.layer?.sublayers?.first }
    }

    override func layout() {
        super.layout()
        // Resize background layer to fill
        if let bg = layer?.sublayers?.first {
            bg.frame = bounds
        }
    }

    private func setupContent() {
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.wantsLayer = true
        contentContainer.alphaValue = 0 // starts hidden, faded in during expand
        addSubview(contentContainer)
        NSLayoutConstraint.activate([
            contentContainer.topAnchor.constraint(equalTo: topAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: bottomAnchor),
            contentContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        if side == .left {
            setupLeftContent()
        } else {
            setupRightContent()
        }
    }

    // MARK: - Left wing: status dots · separator · pending badge

    private func setupLeftContent() {
        // Badge (rightmost in left wing)
        badgeBg.wantsLayer = true
        badgeBg.layer?.backgroundColor = NSColor(red: 245/255, green: 158/255, blue: 11/255, alpha: 1).cgColor
        badgeBg.layer?.cornerRadius = 10
        badgeBg.translatesAutoresizingMaskIntoConstraints = false
        badgeBg.isHidden = true
        contentContainer.addSubview(badgeBg)

        badgeLabel.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        badgeLabel.textColor = .black
        badgeLabel.alignment = .center
        badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        badgeLabel.isBordered = false
        badgeLabel.drawsBackground = false
        badgeBg.addSubview(badgeLabel)

        // Separator
        separatorView.wantsLayer = true
        separatorView.layer?.backgroundColor = NSColor(white: 1, alpha: 0.15).cgColor
        separatorView.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(separatorView)

        NSLayoutConstraint.activate([
            // Badge on the left side of left wing
            badgeBg.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor, constant: 8),
            badgeBg.centerYAnchor.constraint(equalTo: contentContainer.centerYAnchor),
            badgeBg.heightAnchor.constraint(equalToConstant: 16),
            badgeBg.widthAnchor.constraint(greaterThanOrEqualToConstant: 20),

            badgeLabel.centerXAnchor.constraint(equalTo: badgeBg.centerXAnchor),
            badgeLabel.centerYAnchor.constraint(equalTo: badgeBg.centerYAnchor),
            badgeLabel.leadingAnchor.constraint(equalTo: badgeBg.leadingAnchor, constant: 5),
            badgeLabel.trailingAnchor.constraint(equalTo: badgeBg.trailingAnchor, constant: -5),

            // Separator
            separatorView.leadingAnchor.constraint(equalTo: badgeBg.trailingAnchor, constant: 6),
            separatorView.centerYAnchor.constraint(equalTo: contentContainer.centerYAnchor),
            separatorView.widthAnchor.constraint(equalToConstant: 1),
            separatorView.heightAnchor.constraint(equalToConstant: 12),
        ])

        // Dot container (will be populated dynamically)
    }

    // MARK: - Right wing: "agents" label · separator · chevron

    private func setupRightContent() {
        agentsLabel.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        agentsLabel.textColor = NSColor(white: 1, alpha: 0.5)
        agentsLabel.translatesAutoresizingMaskIntoConstraints = false
        agentsLabel.isBordered = false
        agentsLabel.drawsBackground = false
        contentContainer.addSubview(agentsLabel)

        let sep = NSView()
        sep.wantsLayer = true
        sep.layer?.backgroundColor = NSColor(white: 1, alpha: 0.15).cgColor
        sep.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(sep)

        chevronLabel.font = NSFont.systemFont(ofSize: 10)
        chevronLabel.textColor = NSColor(white: 1, alpha: 0.5)
        chevronLabel.translatesAutoresizingMaskIntoConstraints = false
        chevronLabel.isBordered = false
        chevronLabel.drawsBackground = false
        contentContainer.addSubview(chevronLabel)

        NSLayoutConstraint.activate([
            // Right-align: chevron at trailing edge, then separator, then label
            chevronLabel.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor, constant: -8),
            chevronLabel.centerYAnchor.constraint(equalTo: contentContainer.centerYAnchor),

            sep.trailingAnchor.constraint(equalTo: chevronLabel.leadingAnchor, constant: -6),
            sep.centerYAnchor.constraint(equalTo: contentContainer.centerYAnchor),
            sep.widthAnchor.constraint(equalToConstant: 1),
            sep.heightAnchor.constraint(equalToConstant: 12),

            agentsLabel.trailingAnchor.constraint(equalTo: sep.leadingAnchor, constant: -6),
            agentsLabel.centerYAnchor.constraint(equalTo: contentContainer.centerYAnchor),
        ])
    }

    // MARK: - Corner radius control

    /// Remove bottom corner radius so the wing connects flush with the tray.
    func setCornerRadius(_ radius: CGFloat) {
        if let bg = layer?.sublayers?.first {
            bg.cornerRadius = radius
        }
    }

    // MARK: - Public API

    func updateDots(_ states: [DotState]) {
        guard side == .left else { return }

        // Remove old dots
        dotLayers.forEach { $0.removeFromSuperlayer() }
        dotLayers.removeAll()

        guard !states.isEmpty else { return }

        let dotSize: CGFloat = 7
        let spacing: CGFloat = 5
        let separatorTrailing = separatorView.frame.maxX + 6
        let baseX = separatorTrailing > 6 ? separatorTrailing : 40 // fallback when not laid out

        for (i, state) in states.enumerated() {
            let dot = CALayer()
            dot.cornerRadius = dotSize / 2
            dot.frame = CGRect(x: baseX + CGFloat(i) * (dotSize + spacing),
                               y: (NotchPanel.collapsedHeight - dotSize) / 2,
                               width: dotSize, height: dotSize)

            switch state {
            case .running:
                dot.backgroundColor = NSColor(red: 74/255, green: 222/255, blue: 128/255, alpha: 1).cgColor
            case .waiting:
                dot.backgroundColor = NSColor(red: 251/255, green: 191/255, blue: 36/255, alpha: 1).cgColor
            case .idle:
                dot.backgroundColor = NSColor(white: 1, alpha: 0.2).cgColor
            }

            contentContainer.layer?.addSublayer(dot)
            dotLayers.append(dot)
        }
    }

    func updateBadge(count: Int) {
        guard side == .left else { return }
        if count == 0 {
            badgeBg.isHidden = true
        } else {
            badgeBg.isHidden = false
            badgeLabel.stringValue = "\(count)"
        }
    }

    func setChevronUp(_ up: Bool) {
        guard side == .right else { return }
        chevronLabel.stringValue = up ? "▴" : "▾"
    }

    // MARK: - Pulse animation

    func pulseAmberDot() {
        AudioEngine.shared.playNewRequest()
        // Find the first amber dot and pulse it
        for dot in dotLayers {
            let amberColor = NSColor(red: 251/255, green: 191/255, blue: 36/255, alpha: 1).cgColor
            if let bg = dot.backgroundColor, bg == amberColor {
                let pulse = CAKeyframeAnimation(keyPath: "transform.scale")
                pulse.values = [1.0, 1.8, 1.0]
                pulse.keyTimes = [0, 0.5, 1.0]
                pulse.duration = 0.45
                pulse.repeatCount = 2
                dot.add(pulse, forKey: "pulse")
                break
            }
        }
    }
}
