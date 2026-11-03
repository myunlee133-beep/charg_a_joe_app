import XCTest

final class AccountUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    func testLoginReferenceLayoutAndValidation() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-preview-login"]
        app.launch()
        let email = app.textFields["account-email"]
        XCTAssertTrue(email.waitForExistence(timeout: 25))
        let next = app.buttons["account-continue"]
        XCTAssertFalse(next.isEnabled)
        email.tap(); email.typeText("invalid")
        XCTAssertFalse(next.isEnabled)
        email.tap()
        if let clear = email.buttons.allElementsBoundByIndex.first { clear.tap() }
        email.press(forDuration: 1.2)
        // Relaunch to keep the test independent of localized edit-menu labels.
        app.terminate(); app.launch()
        XCTAssertTrue(email.waitForExistence(timeout: 25))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "login-reference"; screenshot.lifetime = .keepAlways; add(screenshot)
        email.tap(); email.typeText("preview@example.invalid")
        XCTAssertTrue(next.isEnabled); next.tap()
        XCTAssertTrue(app.secureTextFields["account-password"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["비밀번호 찾기"].exists)
        app.buttons["처음이신가요? 회원가입"].tap()
        XCTAssertTrue(app.switches["[필수] 만 19세 이상입니다"].exists)
        XCTAssertFalse(next.isEnabled)
        // No real sign-up, email send, policy acceptance or financial operation is submitted.
    }

    func testPrivacyPolicyIsReadableBeforeAuthentication() throws {
        let app = XCUIApplication(); app.launchArguments = ["-preview-login"]; app.launch()
        let policy = app.buttons["개인정보 처리방침"]
        if !policy.waitForExistence(timeout: 20) { app.swipeUp() }
        XCTAssertTrue(policy.waitForExistence(timeout: 5)); policy.tap()
        XCTAssertTrue(app.navigationBars["약관 및 개인정보"].waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "privacy-before-login"; screenshot.lifetime = .keepAlways; add(screenshot)
        XCTAssertTrue(app.buttons["닫기"].exists)
    }
}
