import XCTest

@testable import AIKeyboardCore

/// Keyboard chrome never waits on a transition. The language-switch spring was
/// 300ms and `quick` was 180ms; both felt like watching the keys arrive.
final class MotionTests: XCTestCase {

    /// 0.18 was the old `quick` and still waited. 0.30 was the swipe spring.
    /// A duration at or above either is the build this test exists to reject.
    func testTheSharedBeatIsABlinkNotAWait() {
        XCTAssertEqual(
            Theme.Motion.duration, 0.08,
            "0.18 felt like waiting; the 0.30 swipe spring was a show")
        XCTAssertLessThan(
            Theme.Motion.duration, 0.18,
            "anything as long as the old `quick` is the wait this test named")
    }

    /// The emoji tab pin has to outlast the scroll jump, not the old 180ms fade.
    func testTheEmojiTabPinCoversTheSnapAndNotTheOldFade() {
        XCTAssertEqual(EmojiPanel.pinHold, Theme.Motion.duration + 0.04)
        XCTAssertLessThan(EmojiPanel.pinHold, 0.18)
    }
}
