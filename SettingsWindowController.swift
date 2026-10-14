import Cocoa

/// Menu-accessible window exposing the tap-detection thresholds persisted
/// through `ConfigurationManager`. Changes apply live: `MultitouchManager`
/// observes the configuration-change notification on its touch queue.
///
/// Before this window existed, the persisted configuration could only be
/// changed by hand-editing UserDefaults, and the README still told users to
/// edit constants that no longer exist in source.
@MainActor
final class SettingsWindowController: NSWindowController {

    private struct SliderSpec {
        let title: String
        let unit: String
        let decimals: Int
        let minimumValue: Double
        let maximumValue: Double
        let read: (TapConfiguration) -> Double
        let write: (inout TapConfiguration, Double) -> Void
    }

    private let specs: [SliderSpec] = [
        SliderSpec(
            title: "Max Tap Duration",
            unit: "s",
            decimals: 2,
            minimumValue: 0.15,
            maximumValue: 0.6,
            read: { $0.tapTimeThreshold },
            write: { $0.tapTimeThreshold = $1 }
        ),
        SliderSpec(
            title: "Movement Tolerance",
            unit: "px",
            decimals: 0,
            minimumValue: 3,
            maximumValue: 20,
            read: { Double($0.tapMovementThreshold) },
            write: { $0.tapMovementThreshold = CGFloat($1) }
        ),
        SliderSpec(
            title: "Right-Click Hold Time",
            unit: "s",
            decimals: 2,
            minimumValue: 0.05,
            maximumValue: 0.3,
            read: { $0.rightClickTimeThreshold },
            write: { $0.rightClickTimeThreshold = $1 }
        ),
        SliderSpec(
            title: "Double-Tap Window",
            unit: "s",
            decimals: 2,
            minimumValue: 0.15,
            maximumValue: 0.6,
            read: { $0.doubleTapTimeWindow },
            write: { $0.doubleTapTimeWindow = $1 }
        ),
        SliderSpec(
            title: "Left/Right Boundary",
            unit: "%",
            decimals: 0,
            minimumValue: 40,
            maximumValue: 80,
            read: { Double($0.rightClickAreaThreshold) * 100.0 },
            write: { $0.rightClickAreaThreshold = Float($1 / 100.0) }
        ),
        SliderSpec(
            title: "Surface Movement Limit",
            unit: "%",
            decimals: 0,
            minimumValue: 1,
            maximumValue: 15,
            read: { Double($0.surfaceMovementThreshold) * 100.0 },
            write: { $0.surfaceMovementThreshold = Float($1 / 100.0) }
        ),
        SliderSpec(
            title: "Surface Path Limit",
            unit: "%",
            decimals: 0,
            minimumValue: 4,
            maximumValue: 25,
            read: { Double($0.surfacePathThreshold) * 100.0 },
            write: { $0.surfacePathThreshold = Float($1 / 100.0) }
        ),
        SliderSpec(
            title: "Scroll Velocity Limit",
            unit: "/s",
            decimals: 1,
            minimumValue: 0.3,
            maximumValue: 3.0,
            read: { Double($0.scrollVelocityThreshold) },
            write: { $0.scrollVelocityThreshold = Float($1) }
        ),
        SliderSpec(
            title: "Min Tap Duration",
            unit: "s",
            decimals: 2,
            minimumValue: 0.01,
            maximumValue: 0.10,
            read: { $0.minTapDuration },
            write: { $0.minTapDuration = $1 }
        ),
    ]

    private let zoomEnabledButton = NSButton(checkboxWithTitle: "Enable Two-Finger Zoom", target: nil, action: nil)
    private let zoomReversedButton = NSButton(checkboxWithTitle: "Reverse zoom direction", target: nil, action: nil)
    private let zoomSlider = NSSlider(value: 1, minValue: 0.5, maxValue: 2, target: nil, action: nil)
    private let zoomValue = NSTextField(labelWithString: "1.00×")

    private var sliders: [NSSlider] = []
    private var valueLabels: [NSTextField] = []
    private var pendingCommit: DispatchWorkItem?

    /// Debounce interval: slider drags tick continuously, and every committed
    /// value writes to UserDefaults and wakes the touch queue.
    private let commitDelay: TimeInterval = 0.25

    init() {
        let contentViewController = NSViewController()
        let window = NSWindow(contentViewController: contentViewController)
        window.title = "Sensitivity Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self

        buildContent(in: contentViewController.view)
        reloadFromConfiguration()
        NotificationCenter.default.addObserver(self, selector: #selector(configurationChanged),
            name: ConfigurationManager.configurationDidChangeNotification, object: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        pendingCommit?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - UI Construction

    private func buildContent(in contentView: NSView) {
        let headerLabel = NSTextField(labelWithString: "Fine-tune how taps are detected. Changes apply immediately.")
        headerLabel.font = NSFont.systemFont(ofSize: 11)
        headerLabel.textColor = .secondaryLabelColor

        let footnoteLabel = NSTextField(labelWithString: "Taps that move farther or last longer than these limits are treated as scrolling and ignored.")
        footnoteLabel.font = NSFont.systemFont(ofSize: 10)
        footnoteLabel.textColor = .secondaryLabelColor

        let grid = NSGridView()
        grid.columnSpacing = 12
        grid.rowSpacing = 14

        let config = ConfigurationManager.shared.current
        for (index, spec) in specs.enumerated() {
            let titleLabel = NSTextField(labelWithString: spec.title)
            titleLabel.font = NSFont.systemFont(ofSize: 12)

            let slider = NSSlider(
                value: spec.read(config),
                minValue: spec.minimumValue,
                maxValue: spec.maximumValue,
                target: self,
                action: #selector(sliderChanged(_:))
            )
            slider.isContinuous = true
            slider.tag = index

            let valueLabel = NSTextField(labelWithString: "")
            valueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            valueLabel.alignment = .right

            sliders.append(slider)
            valueLabels.append(valueLabel)
            grid.addRow(with: [titleLabel, slider, valueLabel])
        }

        grid.column(at: 0).xPlacement = .leading
        grid.column(at: 1).xPlacement = .fill
        grid.column(at: 2).xPlacement = .trailing
        grid.column(at: 0).width = 160
        grid.column(at: 2).width = 56

        let resetButton = NSButton(title: "Reset to Defaults", target: self, action: #selector(resetToDefaults(_:)))
        resetButton.bezelStyle = .rounded

        zoomEnabledButton.target = self
        zoomEnabledButton.action = #selector(zoomSettingsChanged)
        zoomReversedButton.target = self
        zoomReversedButton.action = #selector(zoomSettingsChanged)
        zoomSlider.target = self
        zoomSlider.action = #selector(zoomSettingsChanged)
        zoomSlider.isContinuous = false
        let zoomRow = NSStackView(views: [NSTextField(labelWithString: "Zoom sensitivity"), zoomSlider, zoomValue])
        zoomRow.orientation = .horizontal
        zoomSlider.widthAnchor.constraint(equalToConstant: 180).isActive = true
        let zoomHelp = NSTextField(wrappingLabelWithString: "Slide both fingers toward the front to zoom in. Lift both fingers before starting again. Works in apps that support pinch zoom.")
        zoomHelp.preferredMaxLayoutWidth = 420
        zoomHelp.widthAnchor.constraint(lessThanOrEqualToConstant: 420).isActive = true
        zoomHelp.font = NSFont.systemFont(ofSize: 11)
        zoomHelp.textColor = .secondaryLabelColor
        let stackView = NSStackView(views: [headerLabel, grid, footnoteLabel,
            zoomEnabledButton, zoomReversedButton, zoomRow, zoomHelp, resetButton])
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 14
        stackView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            stackView.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -20),
            grid.trailingAnchor.constraint(equalTo: stackView.trailingAnchor),
        ])

        window?.setContentSize(NSSize(width: 460, height: contentView.fittingSize.height))
    }

    // MARK: - Actions

    @objc private func configurationChanged() {
        // Menu toggles must update this window, without overwriting an uncommitted tap slider.
        reloadZoomSettings()
    }

    @objc private func zoomSettingsChanged() {
        var config = ConfigurationManager.shared.current
        config.zoomEnabled = zoomEnabledButton.state == .on
        config.zoomReversed = zoomReversedButton.state == .on
        config.zoomSensitivity = zoomSlider.doubleValue
        ConfigurationManager.shared.update(config)
    }

    private func reloadZoomSettings() {
        let config = ConfigurationManager.shared.current
        zoomEnabledButton.state = config.zoomEnabled ? .on : .off
        zoomReversedButton.state = config.zoomReversed ? .on : .off
        zoomSlider.doubleValue = config.zoomSensitivity
        zoomValue.stringValue = String(format: "%.2f×", config.zoomSensitivity)
    }

    @objc private func sliderChanged(_ sender: NSSlider) {
        let index = sender.tag
        guard specs.indices.contains(index) else { return }

        updateValueLabel(index: index, value: sender.doubleValue)

        pendingCommit?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.commit(index: index, value: sender.doubleValue)
        }
        pendingCommit = work
        DispatchQueue.main.asyncAfter(deadline: .now() + commitDelay, execute: work)
    }

    private func commit(index: Int, value: Double) {
        let spec = specs[index]
        var config = ConfigurationManager.shared.current
        spec.write(&config, value)
        ConfigurationManager.shared.update(config)
    }

    @objc private func resetToDefaults(_ sender: NSButton) {
        pendingCommit?.cancel()
        ConfigurationManager.shared.resetToDefaults()
        reloadFromConfiguration()
    }

    // MARK: - Refresh

    private func reloadFromConfiguration() {
        reloadZoomSettings()
        let config = ConfigurationManager.shared.current
        for (index, spec) in specs.enumerated() {
            let value = spec.read(config)
            sliders[index].doubleValue = value
            updateValueLabel(index: index, value: value)
        }
    }

    private func updateValueLabel(index: Int, value: Double) {
        let spec = specs[index]
        valueLabels[index].stringValue = String(format: "%.\(spec.decimals)f %@", value, spec.unit as NSString)
    }
}

extension SettingsWindowController: NSWindowDelegate {
    /// A slider change is committed after a debounce delay; closing the window
    /// inside that window would otherwise silently drop the final value.
    func windowWillClose(_ notification: Notification) {
        pendingCommit?.cancel()
        pendingCommit = nil
        for (index, slider) in sliders.enumerated() {
            commit(index: index, value: slider.doubleValue)
        }
    }
}
