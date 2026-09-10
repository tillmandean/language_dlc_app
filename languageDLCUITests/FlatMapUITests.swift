import XCTest

/// Milestone A: toggling a language must re-render the map without freezing the UI.
final class FlatMapUITests: XCTestCase {

    @MainActor
    func testTogglingLanguageUpdatesTheMap() throws {
        let app = XCUIApplication()
        app.launch()

        let spanish = app.buttons["Spanish"]
        XCTAssertTrue(spanish.waitForExistence(timeout: 15))

        let summary = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS %@", "of the world")).firstMatch
        XCTAssertTrue(summary.waitForExistence(timeout: 15))
        let before = summary.label

        spanish.tap()

        let changed = expectation(for: NSPredicate(format: "label != %@", before),
                                  evaluatedWith: summary)
        wait(for: [changed], timeout: 10)
        XCTAssertNotEqual(summary.label, before)

        // The app is still responsive: toggle back and the summary returns to where it started.
        spanish.tap()
        let restored = expectation(for: NSPredicate(format: "label == %@", before),
                                   evaluatedWith: summary)
        wait(for: [restored], timeout: 10)
    }
}
