//
//  TaskFlowUITestsLaunchTests.swift
//  TaskFlowUITests
//
//  Created by Masahiro Mura on 2026/07/12.
//

import XCTest

/// 起動直後の画面を撮って残す
///
/// 向きや外観を切り替えながら何度も起動すると、シミュレータが横向きのまま残ってしまうので、
/// 1回だけ、縦向きで起動する。ふだんのデータに触れないよう `-uiTesting` で起動する。
final class TaskFlowUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        false
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDownWithError() throws {
        // 次にアプリを開いたときに横向きにならないよう、縦に戻しておく
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-uiTestingSeed"]
        app.launch()

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
