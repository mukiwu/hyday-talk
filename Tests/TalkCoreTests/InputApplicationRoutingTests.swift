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
