import XCTest

/// Toggling a language must re-render the map without freezing the UI — the globe's texture
/// is rebuilt off the main thread, so the app has to stay responsive throughout.
final class MapInteractionUITests: XCTestCase {

    @MainActor
    func testTogglingLanguageUpdatesTheMap() throws {
        let app = XCUIApplication()
        app.launch()

        let summary = app.staticTexts["worldSummary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 15))
        let before = summary.label

        app.buttons["Languages"].tap()
        let spanish = app.buttons["Spanish"]
        XCTAssertTrue(spanish.waitForExistence(timeout: 10))
        spanish.tap()

        let changed = expectation(for: NSPredicate(format: "label != %@", before),
                                  evaluatedWith: summary)
        wait(for: [changed], timeout: 10)
        XCTAssertNotEqual(summary.label, before)

        // The app is still responsive: toggle back (now in the pinned "Selected" section) and
        // the summary returns to where it started.
        let selectedSpanish = app.buttons["Spanish"]
        XCTAssertTrue(selectedSpanish.waitForExistence(timeout: 10))
        selectedSpanish.tap()
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

    /// §9.2: the accessible alternative to the globe. Toggling to it must show a plain list
    /// of countries and toggling back must restore the globe.
    @MainActor
    func testListModeTogglesTheAccessibleCountryList() throws {
        let app = XCUIApplication()
        app.launch()

        let listButton = app.buttons["List"]
        XCTAssertTrue(listButton.waitForExistence(timeout: 15))
        listButton.tap()

        let list = app.descendants(matching: .any).matching(identifier: "countryList").firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 10))
        XCTAssertTrue(list.cells.count > 0)

        let globeButton = app.buttons["Globe"]
        XCTAssertTrue(globeButton.waitForExistence(timeout: 5))
        globeButton.tap()
        XCTAssertFalse(list.exists)
    }

    /// §9.4: the data caveat sheet must be reachable and dismissible without disturbing the map.
    @MainActor
    func testAttributionSheetOpensAndDismisses() throws {
        let app = XCUIApplication()
        app.launch()

        let infoButton = app.buttons["Data & credits"]
        XCTAssertTrue(infoButton.waitForExistence(timeout: 15))
        infoButton.tap()

        let title = app.navigationBars["Data & credits"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))

        app.swipeDown(velocity: .fast)
        XCTAssertTrue(waitForDisappearance(of: title, timeout: 5))
    }

    private func waitForDisappearance(of element: XCUIElement, timeout: TimeInterval) -> Bool {
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: element)
        return XCTWaiter().wait(for: [gone], timeout: timeout) == .completed
    }
}
