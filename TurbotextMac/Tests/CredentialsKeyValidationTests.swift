import XCTest
@testable import Turbotext

final class CredentialsKeyValidationTests: XCTestCase {

    func testValidGroqKeyIsAccepted() {
        let key = "gsk_" + String(repeating: "a", count: 20)
        XCTAssertEqual(
            CredentialsSettingsView.validatedKey(fromClipboardText: key, pattern: CredentialsSettingsView.groqAPIKeyPattern),
            key
        )
    }

    func testValidOpenAIKeyIsAccepted() {
        let key = "sk-" + String(repeating: "a", count: 20)
        XCTAssertEqual(
            CredentialsSettingsView.validatedKey(fromClipboardText: key, pattern: CredentialsSettingsView.openAIAPIKeyPattern),
            key
        )
    }

    func testInvalidKeyIsRejected() {
        XCTAssertNil(
            CredentialsSettingsView.validatedKey(fromClipboardText: "not-a-key", pattern: CredentialsSettingsView.openAIAPIKeyPattern)
        )
    }

    func testKeyIsTrimmedAndFirstLineOnly() {
        let key = "sk-" + String(repeating: "a", count: 20)
        let clipboard = "  \(key)  \nsome trailing garbage"
        XCTAssertEqual(
            CredentialsSettingsView.validatedKey(fromClipboardText: clipboard, pattern: CredentialsSettingsView.openAIAPIKeyPattern),
            key
        )
    }

    func testWrongPatternIsRejected() {
        let groqKey = "gsk_" + String(repeating: "a", count: 20)
        XCTAssertNil(
            CredentialsSettingsView.validatedKey(fromClipboardText: groqKey, pattern: CredentialsSettingsView.openAIAPIKeyPattern)
        )
    }

    func testCancelButtonShownWhileEditingExistingKey() {
        XCTAssertTrue(CredentialsSettingsView.shouldShowCancelButton(hasExistingValue: true, isEditing: true))
    }

    func testCancelButtonHiddenWhenNotEditing() {
        XCTAssertFalse(CredentialsSettingsView.shouldShowCancelButton(hasExistingValue: true, isEditing: false))
    }

    func testCancelButtonHiddenWhenNoExistingValueToRevertTo() {
        XCTAssertFalse(CredentialsSettingsView.shouldShowCancelButton(hasExistingValue: false, isEditing: true))
    }
}
