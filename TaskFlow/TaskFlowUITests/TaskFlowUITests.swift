import XCTest

/// 主な流れを、実際の画面で確かめる
///
/// アプリは `-uiTesting` で起動し、毎回空の専用の保存先を使う（ふだんのデータには触れない）。
final class TaskFlowUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDownWithError() throws {
        // 次にアプリを開いたときに横向きにならないよう、縦に戻しておく
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor
    private func launch(seeded: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"] + (seeded ? ["-uiTestingSeed"] : [])
        // キーボードを英語にして、入力が崩れないようにする
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleKeyboards", "(en_US@sw=QWERTY;hw=Automatic)"]
        app.launch()
        return app
    }

    @MainActor
    func testCompletingMovesToTheNextTaskAndCanBeUndone() throws {
        let app = launch(seeded: true)
        let title = app.staticTexts["recommendationTitle"]

        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.label, "Write report")

        app.buttons["completeButton"].tap()

        XCTAssertTrue(app.staticTexts["recommendationTitle"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["recommendationTitle"].label, "Read paper")

        let undo = app.buttons["undoButton"]
        XCTAssertTrue(undo.waitForExistence(timeout: 3))
        undo.tap()

        let restored = expectation(
            for: NSPredicate(format: "label == %@", "Write report"),
            evaluatedWith: app.staticTexts["recommendationTitle"]
        )
        wait(for: [restored], timeout: 5)
    }

    @MainActor
    func testQuickAddPutsTheTaskOnTheCard() throws {
        let app = launch(seeded: false)

        // 真ん中下の＋を押すと、入力欄が開いて書ける
        let addButton = app.buttons["addButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()

        let field = app.textFields["quickAddField"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.typeText("Buy milk 10m\n")

        let title = app.staticTexts["recommendationTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.label, "Buy milk")

        // 書き終えたら、また＋に戻る
        XCTAssertTrue(addButton.waitForExistence(timeout: 3))
    }

    @MainActor
    func testDeletingFromTheCardCanBeUndone() throws {
        let app = launch(seeded: true)
        let title = app.staticTexts["recommendationTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.label, "Write report")

        app.buttons["cardMenu"].tap()
        let delete = app.buttons["deleteFromCardButton"]
        XCTAssertTrue(delete.waitForExistence(timeout: 3))
        delete.tap()

        let undo = app.buttons["undoDeleteButton"]
        XCTAssertTrue(undo.waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts["recommendationTitle"].label, "Read paper")
        undo.tap()

        let restored = expectation(
            for: NSPredicate(format: "label == %@", "Write report"),
            evaluatedWith: app.staticTexts["recommendationTitle"]
        )
        wait(for: [restored], timeout: 5)
    }
}
