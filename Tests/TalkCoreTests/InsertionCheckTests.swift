import XCTest
@testable import TalkCore

final class InsertionCheckTests: XCTestCase {
    func testCaretShiftedByOutputAboveStillInserts() {
        // Terminals and chat pages report the caret from the start of all their text, so new
        // output above the field moves the location while the caret stays put.
        XCTAssertNil(InsertionCheck.problem(before: CFRange(location: 120, length: 0), after: CFRange(location: 980, length: 0),
                                            beforeSelection: "", afterSelection: ""))
    }

    func testChangedSelectionKeepsTheText() {
        XCTAssertNotNil(InsertionCheck.problem(before: CFRange(location: 10, length: 5), after: CFRange(location: 10, length: 0),
                                               beforeSelection: "hello", afterSelection: ""))
        XCTAssertNotNil(InsertionCheck.problem(before: CFRange(location: 10, length: 0), after: CFRange(location: 4, length: 3),
                                               beforeSelection: "", afterSelection: "abc"))
    }

    func testSameSelectionMovedByOutputStillInserts() {
        XCTAssertNil(InsertionCheck.problem(before: CFRange(location: 10, length: 5), after: CFRange(location: 60, length: 5),
                                            beforeSelection: "hello", afterSelection: "hello"))
    }
}
