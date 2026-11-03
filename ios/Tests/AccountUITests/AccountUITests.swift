import XCTest

final class AccountUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testLoginIsTheLaunchScreenAndShowsEverySignInMethod() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["account-entry-title"].waitForExistence(timeout: 25))
        let signupLink = app.buttons["account-signup-link"]
        let forgotPassword = app.buttons["account-forgot-password"]
        XCTAssertTrue(signupLink.exists)
        XCTAssertTrue(forgotPassword.exists)
        XCTAssertEqual(signupLink.frame.midY, forgotPassword.frame.midY, accuracy: 2)
        XCTAssertGreaterThan(signupLink.frame.minX, forgotPassword.frame.maxX)
        for provider in ["google", "apple", "kakao"] {
            XCTAssertTrue(app.buttons["account-provider-\(provider)"].exists)
        }
        XCTAssertFalse(app.buttons["홈"].exists, "Home navigation must not be exposed before login")
        XCTAssertFalse(app.buttons["먼저 둘러볼게요"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "login-entry"; screenshot.lifetime = .keepAlways; add(screenshot)

        let email = app.textFields["account-email"]
        let next = app.buttons["account-continue"]
        XCTAssertTrue(email.exists)
        XCTAssertTrue(app.secureTextFields["account-password"].exists)
        XCTAssertFalse(next.isEnabled)
        email.tap(); email.typeText("invalid")
        XCTAssertFalse(next.isEnabled)
        email.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "invalid".count))
        email.typeText("preview@example.invalid")
        XCTAssertFalse(next.isEnabled, "A password is also required")
        let password = app.secureTextFields["account-password"]
        password.tap(); password.typeText("preview-only-password")
        XCTAssertTrue(next.isEnabled)
        if app.buttons["완료"].exists { app.buttons["완료"].tap() }
        // Never submit a login, signup, email or financial operation in UI tests.
    }

    func testSignupHasExplicitConsentAndPrivacyIsReadableBeforeLogin() throws {
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.buttons["account-signup-link"].waitForExistence(timeout: 25))
        app.buttons["account-signup-link"].tap()
        XCTAssertTrue(app.buttons["account-return-login"].exists)
        app.buttons["account-return-login"].tap()
        XCTAssertTrue(app.buttons["account-forgot-password"].exists)
        app.buttons["account-signup-link"].tap()
        app.swipeUp()
        XCTAssertTrue(app.switches["[필수] 만 19세 이상입니다"].exists)
        XCTAssertFalse(app.buttons["account-continue"].isEnabled)
        let signup = XCTAttachment(screenshot: app.screenshot())
        signup.name = "signup-consent"; signup.lifetime = .keepAlways; add(signup)

        let policy = app.buttons["개인정보 처리방침"]
        if !policy.exists { app.swipeUp() }
        XCTAssertTrue(policy.waitForExistence(timeout: 5)); policy.tap()
        XCTAssertTrue(app.navigationBars["약관 및 개인정보"].waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "privacy-before-login"; screenshot.lifetime = .keepAlways; add(screenshot)
        XCTAssertTrue(app.buttons["닫기"].exists)
    }
}
