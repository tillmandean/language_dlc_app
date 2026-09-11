import XCTest

/// Toggling a language must re-render the map without freezing the UI — the globe's texture
/// is rebuilt off the main thread, so the app has to stay responsive throughout.
final class MapInteractionUITests: XCTestCase {

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

    /// End to end through the real globe: a tap on the sphere becomes a texture coordinate and
    /// then a country. The globe idles by spinning, so which land is in front depends on when
    /// the test gets here — hence a grid of taps rather than one.
    @MainActor
    func testTappingTheGlobeIdentifiesACountry() throws {
        let app = XCUIApplication()
        app.launch()

        let label = app.staticTexts["focusedTerritory"]
        XCTAssertTrue(label.waitForExistence(timeout: 15))
        XCTAssertEqual(label.label, "Tap a country")

        for x in stride(from: 0.2, through: 0.8, by: 0.15) {
            for y in stride(from: 0.3, through: 0.55, by: 0.05) {
                app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y)).tap()
                if label.label != "Tap a country" { return }     // landed on a country
            }
        }
        XCTFail("no tap anywhere on the globe resolved to a country, last label: \(label.label)")
    }
}
