import XCTest
@testable import TalkCore

final class InputApplicationRoutingTests: XCTestCase {
    func testRecorderForegroundKeepsThePreviousExternalApplicationAsDestination() {
        XCTAssertEqual(InputApplicationRouting.targetPID(frontmostPID: 100, recorderPID: 100,
                                                         previousExternalPID: 200), 200)
    }
    func testCurrentExternalApplicationTakesPriorityOverAnOldDestination() {
        XCTAssertEqual(InputApplicationRouting.targetPID(frontmostPID: 300, recorderPID: 100,
                                                         previousExternalPID: 200), 300)
    }
    func testNoForegroundOrNoExternalDestinationDoesNotGuessAnApplication() {
        XCTAssertNil(InputApplicationRouting.targetPID(frontmostPID: nil, recorderPID: 100,
                                                       previousExternalPID: 200))
        XCTAssertNil(InputApplicationRouting.targetPID(frontmostPID: 100, recorderPID: 100,
                                                       previousExternalPID: nil))
        XCTAssertNil(InputApplicationRouting.targetPID(frontmostPID: 100, recorderPID: 100,
                                                       previousExternalPID: 100))
    }
}

final class FocusMemoryTests: XCTestCase {
    func testKeepsTheLastFieldWhileTheSameAppReportsNoFocus() {
        // Electron apps such as HyperFrames stop reporting focus about two seconds after activation
        // while the caret stays in the field.
        XCTAssertEqual(FocusMemory.remembered(previous: "field", previousPID: 7, reported: nil, pid: 7), "field")
        XCTAssertEqual(FocusMemory.remembered(previous: "field", previousPID: 7, reported: "other", pid: 7), "other")
    }

    func testTheFieldIsWhatTheAppReportsOrTheRememberedOneWhileItStillHasFocus() {
        XCTAssertEqual(FocusMemory.field(reported: "now", remembered: "before", rememberedHasFocus: false), "now")
        XCTAssertEqual(FocusMemory.field(reported: nil, remembered: "before", rememberedHasFocus: true), "before")
        XCTAssertNil(FocusMemory.field(reported: nil, remembered: "before", rememberedHasFocus: false))
        XCTAssertNil(FocusMemory.field(reported: nil as String?, remembered: nil, rememberedHasFocus: true))
    }

    func testForgetsTheFieldWhenAnotherAppComesForward() {
        XCTAssertNil(FocusMemory.remembered(previous: "field", previousPID: 7, reported: nil as String?, pid: 8))
    }
}
