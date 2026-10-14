import Foundation
import CoreGraphics

/// Mouse gesture state machine
enum MouseState: Equatable {
    case idle                    // 空闲状态
    case touching                // 接触中（单击）
    case secondTapPending        // 第二次轻触，等待判定为双击或拖拽
    case dragging                // 拖拽中
}

/// Result of processing a touch event
struct TouchProcessResult {
    let shouldClick: Bool           // 是否应该触发点击
    let clickLocation: CGPoint?     // 点击位置
    let isRightClick: Bool          // 是否为右键点击
    let clickCount: Int             // 点击次数（无点击为 0，单击为 1，双击第二次为 2）
    let isDragging: Bool            // 是否处于拖拽状态
    let dragLocation: CGPoint?      // 拖拽位置（用于移动光标）
}

/// Handles advanced gesture detection with state machine - separated for testability
class TapDetector {
    // Thresholds (can be updated via updateConfiguration)
    private(set) var tapTimeThreshold: TimeInterval          // 最大点击时长
    private(set) var tapMovementThreshold: CGFloat           // 最大点击移动距离（光标）
    private(set) var rightClickTimeThreshold: TimeInterval   // 右键最小按住时长
    private(set) var doubleTapTimeWindow: TimeInterval       // 双击时间窗口
    private(set) var minTapDuration: TimeInterval            // 最小点击时长（防误触）
    private(set) var dragThreshold: CGFloat                  // 拖拽抖动阈值
    private(set) var quickTapThreshold: TimeInterval         // 快速点击时间阈值

    // State
    private var currentState: MouseState = .idle
    private var touchStartTime: Date?
    private var touchStartLocation: CGPoint?
    private var lastClickTime: Date?
    private var lastClickLocation: CGPoint?
    private var dragStartLocation: CGPoint?
    private var maximumMovementDistance: CGFloat = 0
    /// Total cursor distance travelled during the touch. Displacement-based
    /// checks can be fooled by movement that leaves and returns; a path that
    /// long always means the user was moving the mouse, not tapping it.
    private var cursorPathLength: CGFloat = 0
    private var previousCursorLocation: CGPoint?
    private let nowProvider: () -> Date

    /// A tap may wobble, but its total travel should stay within a small
    /// multiple of the displacement limit.
    private let cursorPathLimitMultiplier: CGFloat = 3.0

    /// Initialize with explicit values (for testing)
    init(
        tapTimeThreshold: TimeInterval = 0.3,
        tapMovementThreshold: CGFloat = 5.0,
        rightClickTimeThreshold: TimeInterval = 0.16,
        doubleTapTimeWindow: TimeInterval = 0.3,
        dragThreshold: CGFloat = 2.0,
        minTapDuration: TimeInterval = 0.03,
        quickTapThreshold: TimeInterval = 0.15,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.tapTimeThreshold = tapTimeThreshold
        self.tapMovementThreshold = tapMovementThreshold
        self.rightClickTimeThreshold = rightClickTimeThreshold
        self.doubleTapTimeWindow = doubleTapTimeWindow
        self.minTapDuration = minTapDuration
        self.dragThreshold = dragThreshold
        self.quickTapThreshold = quickTapThreshold
        self.nowProvider = nowProvider
    }

    /// Initialize from TapConfiguration
    convenience init(configuration: TapConfiguration) {
        self.init(
            tapTimeThreshold: configuration.tapTimeThreshold,
            tapMovementThreshold: configuration.tapMovementThreshold,
            rightClickTimeThreshold: configuration.rightClickTimeThreshold,
            doubleTapTimeWindow: configuration.doubleTapTimeWindow,
            dragThreshold: configuration.dragThreshold,
            minTapDuration: configuration.minTapDuration,
            quickTapThreshold: configuration.quickTapThreshold
        )
    }

    /// Update thresholds from configuration (called when config changes)
    func updateConfiguration(_ config: TapConfiguration) {
        tapTimeThreshold = config.tapTimeThreshold
        tapMovementThreshold = config.tapMovementThreshold
        rightClickTimeThreshold = config.rightClickTimeThreshold
        doubleTapTimeWindow = config.doubleTapTimeWindow
        minTapDuration = config.minTapDuration
        dragThreshold = config.dragThreshold
        quickTapThreshold = config.quickTapThreshold
    }

    /// Process touch began event
    func touchBegan(at location: CGPoint, isRightSide: Bool) -> TouchProcessResult {
        let now = nowProvider()

        // 只有时间和位置都足够接近的左键点击才能组成双击。
        if let lastTime = lastClickTime,
           let lastLocation = lastClickLocation,
           now.timeIntervalSince(lastTime) >= 0,
           now.timeIntervalSince(lastTime) < doubleTapTimeWindow,
           hypot(location.x - lastLocation.x, location.y - lastLocation.y) <= tapMovementThreshold,
           currentState == .idle {
            currentState = .secondTapPending
            touchStartTime = now
            touchStartLocation = location
            dragStartLocation = location
            maximumMovementDistance = 0
            cursorPathLength = 0
            previousCursorLocation = location

            // 第二次触摸已经消费了候选序列；无论最终成为双击、拖拽还是
            // 被取消，之后的触摸都从一个新的点击序列开始。
            clearClickHistory()

            return TouchProcessResult(
                shouldClick: false,
                clickLocation: nil,
                isRightClick: false,
                clickCount: 0,
                isDragging: false,
                dragLocation: nil
            )
        }

        // 不是有效的第二次轻触时，旧候选不再参与后续手势。
        clearClickHistory()
        currentState = .touching
        touchStartTime = now
        touchStartLocation = location
        maximumMovementDistance = 0
        cursorPathLength = 0
        previousCursorLocation = location

        return TouchProcessResult(
            shouldClick: false,
            clickLocation: nil,
            isRightClick: false,
            clickCount: 0,
            isDragging: false,
            dragLocation: nil
        )
    }

    /// Process touch moved event
    func touchMoved(to location: CGPoint) -> TouchProcessResult {
        guard let startLocation = touchStartLocation else {
            return TouchProcessResult(
                shouldClick: false,
                clickLocation: nil,
                isRightClick: false,
                clickCount: 0,
                isDragging: false,
                dragLocation: nil
            )
        }

        if let previous = previousCursorLocation {
            cursorPathLength += hypot(location.x - previous.x, location.y - previous.y)
        }
        previousCursorLocation = location

        switch currentState {
        case .touching:
            let distance = hypot(location.x - startLocation.x, location.y - startLocation.y)
            maximumMovementDistance = max(maximumMovementDistance, distance)
            if distance > tapMovementThreshold {
                #if DEBUG
                print("📍 Significant movement detected: \(String(format: "%.2f", distance)) px")
                #endif
            }

        case .secondTapPending:
            let distance = hypot(location.x - startLocation.x, location.y - startLocation.y)
            maximumMovementDistance = max(maximumMovementDistance, distance)

            if distance > tapMovementThreshold {
                currentState = .dragging
                dragStartLocation = location
                return TouchProcessResult(
                    shouldClick: false,
                    clickLocation: nil,
                    isRightClick: false,
                    clickCount: 0,
                    isDragging: true,
                    dragLocation: location
                )
            }

        case .dragging:
            // 在拖拽状态下，使用更小的防抖阈值，并且总是返回拖拽状态
            if let dragStart = dragStartLocation {
                let dragDistance = hypot(location.x - dragStart.x, location.y - dragStart.y)
                if dragDistance > dragThreshold {
                    // 超过阈值，更新拖拽起点，返回拖拽位置
                    dragStartLocation = location
                    return TouchProcessResult(
                        shouldClick: false,
                        clickLocation: nil,
                        isRightClick: false,
                        clickCount: 0,
                        isDragging: true,
                        dragLocation: location
                    )
                } else {
                    // 即使在阈值内，也保持拖拽状态（防止中断）
                    return TouchProcessResult(
                        shouldClick: false,
                        clickLocation: nil,
                        isRightClick: false,
                        clickCount: 0,
                        isDragging: true,
                        dragLocation: nil  // 小幅移动不更新位置，但保持拖拽状态
                    )
                }
            }

        default:
            break
        }

        return TouchProcessResult(
            shouldClick: false,
            clickLocation: nil,
            isRightClick: false,
            clickCount: 0,
            isDragging: currentState == .dragging,
            dragLocation: nil
        )
    }

    /// Process touch ended event
    func touchEnded(at location: CGPoint, isRightSide: Bool) -> TouchProcessResult {
        guard let startTime = touchStartTime,
              let startLocation = touchStartLocation else {
            reset()
            return TouchProcessResult(
                shouldClick: false,
                clickLocation: nil,
                isRightClick: false,
                clickCount: 0,
                isDragging: false,
                dragLocation: nil
            )
        }

        let now = nowProvider()
        let duration = now.timeIntervalSince(startTime)
        let distance = hypot(location.x - startLocation.x, location.y - startLocation.y)
        maximumMovementDistance = max(maximumMovementDistance, distance)
        if let previous = previousCursorLocation {
            cursorPathLength += hypot(location.x - previous.x, location.y - previous.y)
            previousCursorLocation = location
        }

        var result = TouchProcessResult(
            shouldClick: false,
            clickLocation: nil,
            isRightClick: false,
            clickCount: 0,
            isDragging: false,
            dragLocation: nil
        )

        switch currentState {
        case .touching:
            // 智能点击检测：区分快速点击和滚动
            #if DEBUG
            print("✋ Touch ended. Dist: \(String(format: "%.2f", distance)), Max dist: \(String(format: "%.2f", maximumMovementDistance)), Dur: \(String(format: "%.3f", duration))")
            #endif

            // 智能判定逻辑：
            // 1. 快速点击允许更大的轻微移动，避免手抖造成漏点。
            // 2. 无论持续时间如何，都必须有移动上限，避免移动鼠标时误触。
            // 3. 除位移外还校验累积路程：来回移动可以骗过位移，骗不过路程。
            let isQuickTap = duration < quickTapThreshold
            let movementLimit = isQuickTap ? tapMovementThreshold * 2.0 : tapMovementThreshold
            let isValidTap = maximumMovementDistance <= movementLimit &&
                             cursorPathLength <= movementLimit * cursorPathLimitMultiplier &&
                             duration < tapTimeThreshold &&
                             duration > minTapDuration

            if isValidTap {
                // 右键检测：按住时间较长且在右侧
                if duration >= rightClickTimeThreshold && isRightSide {
                    #if DEBUG
                    print("✅ Right Click Triggered")
                    #endif
                    result = TouchProcessResult(
                        shouldClick: true,
                        clickLocation: location,
                        isRightClick: true,
                        clickCount: 1,
                        isDragging: false,
                        dragLocation: nil
                    )
                } else {
                    // 普通左键点击（快速点击或左侧点击）
                    #if DEBUG
                    print("✅ Left Click Triggered")
                    #endif
                    result = TouchProcessResult(
                        shouldClick: true,
                        clickLocation: location,
                        isRightClick: false,
                        clickCount: 1,
                        isDragging: false,
                        dragLocation: nil
                    )

                    // 记录点击时间，用于双击检测
                    lastClickTime = now
                    lastClickLocation = location
                }
            } else {
                clearClickHistory()
                #if DEBUG
                print("⚠️ Tap ignored. Too far, too long, or moving fast.")
                #endif
            }

        case .secondTapPending:
            // 双击不使用“快速点击放宽移动范围”的规则，以避免轻微移动
            // 被错误解释为双击而不是拖拽。
            let isValidSecondTap = maximumMovementDistance <= tapMovementThreshold &&
                                   cursorPathLength <= tapMovementThreshold * cursorPathLimitMultiplier &&
                                   duration < tapTimeThreshold &&
                                   duration > minTapDuration

            if isValidSecondTap,
               duration >= rightClickTimeThreshold,
               isRightSide {
                // 第二次触摸位于右键区域且满足按住时长时，保留现有右键行为。
                result = TouchProcessResult(
                    shouldClick: true,
                    clickLocation: location,
                    isRightClick: true,
                    clickCount: 1,
                    isDragging: false,
                    dragLocation: nil
                )
            } else if isValidSecondTap {
                result = TouchProcessResult(
                    shouldClick: true,
                    clickLocation: location,
                    isRightClick: false,
                    clickCount: 2,
                    isDragging: false,
                    dragLocation: nil
                )
            }

        case .dragging:
            // 拖拽结束
            result = TouchProcessResult(
                shouldClick: false,
                clickLocation: nil,
                isRightClick: false,
                clickCount: 0,
                isDragging: false,
                dragLocation: nil
            )

        default:
            break
        }

        resetActiveTouch()
        return result
    }

    /// Cancels the current gesture and any pending double-tap sequence.
    func reset() {
        resetActiveTouch()
        clearClickHistory()
    }

    private func resetActiveTouch() {
        currentState = .idle
        touchStartTime = nil
        touchStartLocation = nil
        dragStartLocation = nil
        maximumMovementDistance = 0
        cursorPathLength = 0
        previousCursorLocation = nil
    }

    private func clearClickHistory() {
        lastClickTime = nil
        lastClickLocation = nil
    }

    /// Returns current mouse state
    var state: MouseState {
        return currentState
    }

    /// Returns true if a touch is currently being tracked
    var isTracking: Bool {
        return currentState != .idle
    }

    /// Returns true if currently dragging
    var isDragging: Bool {
        return currentState == .dragging
    }

    /// Returns true while the second touch is waiting to become a double-click or drag.
    var isSecondTapPending: Bool {
        return currentState == .secondTapPending
    }
}
