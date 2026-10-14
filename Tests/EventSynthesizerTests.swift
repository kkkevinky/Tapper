import XCTest
import CoreGraphics

@testable import TapperLib

final class EventSynthesizerTests: XCTestCase {

    private final class EventRecorder {
        var events: [(type: CGEventType, clickState: Int64, location: CGPoint)] = []

        func record(_ event: CGEvent) {
            events.append((event.type, event.getIntegerValueField(.mouseEventClickState), event.location))
        }
    }

    private var recorder: EventRecorder!
    private var synthesizer: EventSynthesizer!

    override func setUp() {
        super.setUp()
        recorder = EventRecorder()
        // nil event source + injected poster: constructing events is safe in
        // tests, but posting real HID events would move the user's cursor.
        let recorder = recorder!
        synthesizer = EventSynthesizer(eventSource: nil) { event in
            recorder.record(event)
        }
    }

    override func tearDown() {
        synthesizer = nil
        recorder = nil
        super.tearDown()
    }

    // MARK: - Clicks

    func testClickPostsDownThenUpWithClickState() {
        synthesizer.synthesizeClick(at: CGPoint(x: 10, y: 20), isRightClick: false, clickCount: 1)

        XCTAssertEqual(recorder.events.map(\.type), [.leftMouseDown, .leftMouseUp])
        XCTAssertEqual(recorder.events.map(\.clickState), [1, 1])
        XCTAssertEqual(recorder.events[0].location, recorder.events[1].location)
    }

    func testRightClickUsesRightButtonEvents() {
        synthesizer.synthesizeClick(at: CGPoint(x: 5, y: 5), isRightClick: true, clickCount: 1)

        XCTAssertEqual(recorder.events.map(\.type), [.rightMouseDown, .rightMouseUp])
    }

    func testDoubleClickCarriesClickStateTwo() {
        synthesizer.synthesizeClick(at: CGPoint(x: 5, y: 5), isRightClick: false, clickCount: 2)

        XCTAssertEqual(recorder.events.map(\.clickState), [2, 2])
    }

    func testClickCountBelowOneIsClampedToOne() {
        synthesizer.synthesizeClick(at: CGPoint(x: 5, y: 5), isRightClick: false, clickCount: 0)

        XCTAssertEqual(recorder.events.map(\.clickState), [1, 1])
    }

    // MARK: - Drags

    func testDragLifecyclePostsDownDraggedUp() {
        synthesizer.startDrag(at: CGPoint(x: 1, y: 1))
        synthesizer.moveDrag(to: CGPoint(x: 2, y: 2))
        synthesizer.moveDrag(to: CGPoint(x: 3, y: 3))
        synthesizer.endDrag(at: CGPoint(x: 3, y: 3))

        XCTAssertEqual(recorder.events.map(\.type), [.leftMouseDown, .leftMouseDragged, .leftMouseDragged, .leftMouseUp])
    }

    func testMoveAndEndWithoutStartAreIgnored() {
        synthesizer.moveDrag(to: CGPoint(x: 1, y: 1))
        synthesizer.endDrag(at: CGPoint(x: 1, y: 1))

        XCTAssertTrue(recorder.events.isEmpty)
    }

    func testStartDragTwicePostsSingleMouseDown() {
        synthesizer.startDrag(at: CGPoint(x: 1, y: 1))
        synthesizer.startDrag(at: CGPoint(x: 2, y: 2))

        XCTAssertEqual(recorder.events.map(\.type), [.leftMouseDown])
    }

    func testEndDragAllowsNewDragToStart() {
        synthesizer.startDrag(at: CGPoint(x: 1, y: 1))
        synthesizer.endDrag(at: CGPoint(x: 1, y: 1))
        synthesizer.startDrag(at: CGPoint(x: 2, y: 2))

        XCTAssertEqual(recorder.events.map(\.type), [.leftMouseDown, .leftMouseUp, .leftMouseDown])
    }

    // MARK: - Cancel

    func testCancelEndsActiveDragExactlyOnce() {
        synthesizer.startDrag(at: CGPoint(x: 1, y: 1))
        synthesizer.cancelActiveDrag()
        synthesizer.cancelActiveDrag()

        XCTAssertEqual(recorder.events.map(\.type), [.leftMouseDown, .leftMouseUp])
    }

    func testCancelWithoutDragPostsNothing() {
        synthesizer.cancelActiveDrag()

        XCTAssertTrue(recorder.events.isEmpty)
    }
}
