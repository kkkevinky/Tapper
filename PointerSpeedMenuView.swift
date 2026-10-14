import Cocoa

final class PointerSpeedMenuView: NSView {
    var onSpeedChanged: ((Double) -> Bool)?
    var onRestoreDefault: (() -> Double?)?

    private let titleLabel = NSTextField(labelWithString: "Pointer Speed")
    private let valueLabel = NSTextField(labelWithString: "")
    private let slider = NSSlider(value: MouseSpeedManager.fallbackSpeed,
                                  minValue: MouseSpeedManager.minimumSpeed,
                                  maxValue: MouseSpeedManager.maximumSpeed,
                                  target: nil,
                                  action: nil)
    private let restoreButton = NSButton(title: "Restore Default", target: nil, action: nil)
    private var lastSuccessfulValue: Double

    /// Debounce interval: while the slider is being dragged (continuous ticks),
    /// we defer the costly `onSpeedChanged` write (IOHIDSystem call + UserDefaults
    /// flush) until the user pauses or releases. UI label stays live.
    private let commitDelay: TimeInterval = 0.25
    private var pendingCommit: DispatchWorkItem?

    init(currentSpeed: Double) {
        lastSuccessfulValue = MouseSpeedManager.clamp(currentSpeed)
        super.init(frame: NSRect(x: 0, y: 0, width: 260, height: 86))

        setupView()
        setSpeed(lastSuccessfulValue)
    }

    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        pendingCommit?.cancel()
    }

    func setSpeed(_ speed: Double) {
        let clampedSpeed = MouseSpeedManager.clamp(speed)
        lastSuccessfulValue = clampedSpeed
        slider.doubleValue = clampedSpeed
        updateValueLabel(clampedSpeed)
    }

    private func setupView() {
        titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        valueLabel.alignment = .right
        valueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)

        slider.target = self
        slider.action = #selector(sliderChanged)
        slider.isContinuous = true
        slider.numberOfTickMarks = 5
        slider.allowsTickMarkValuesOnly = false

        restoreButton.target = self
        restoreButton.action = #selector(restoreDefault)
        restoreButton.bezelStyle = .rounded
        restoreButton.controlSize = .small
        restoreButton.font = NSFont.systemFont(ofSize: 11)

        [titleLabel, valueLabel, slider, restoreButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 10),

            valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            valueLabel.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            valueLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 12),

            slider.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            slider.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            slider.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),

            restoreButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            restoreButton.topAnchor.constraint(equalTo: slider.bottomAnchor, constant: 8)
        ])
    }

    @objc private func sliderChanged() {
        let newValue = MouseSpeedManager.clamp(slider.doubleValue)
        updateValueLabel(newValue)

        // During an active drag the event type is .leftMouseDragged; debounce
        // the backend write so we don't hammer IOHIDSystem on every tick.
        // Any other event (initial click, release, programmatic) commits now.
        if NSApp.currentEvent?.type == .leftMouseDragged {
            scheduleCommit(newValue)
        } else {
            commitValueNow(newValue)
        }
    }

    private func commitValueNow(_ value: Double) {
        cancelPendingCommit()
        if onSpeedChanged?(value) == true {
            lastSuccessfulValue = value
        } else {
            slider.doubleValue = lastSuccessfulValue
            updateValueLabel(lastSuccessfulValue)
        }
    }

    private func scheduleCommit(_ value: Double) {
        cancelPendingCommit()
        let work = DispatchWorkItem { [weak self] in
            self?.commitValueNow(value)
        }
        pendingCommit = work
        DispatchQueue.main.asyncAfter(deadline: .now() + commitDelay, execute: work)
    }

    private func cancelPendingCommit() {
        pendingCommit?.cancel()
        pendingCommit = nil
    }

    @objc private func restoreDefault() {
        cancelPendingCommit()
        guard let restoredValue = onRestoreDefault?() else {
            slider.doubleValue = lastSuccessfulValue
            updateValueLabel(lastSuccessfulValue)
            return
        }

        setSpeed(restoredValue)
    }

    private func updateValueLabel(_ speed: Double) {
        valueLabel.stringValue = String(format: "%.1f", speed)
    }
}
