import XCTest
@testable import Turbotext

final class MenuBarIdleTooltipTests: XCTestCase {

    func testReadyWhenAllPermissionsGrantedAndNoQuotaInfo() {
        let text = MenuBarIdleTooltip.text(
            accessibilityGranted: true,
            inputMonitoringGranted: true,
            cloudIndicator: .none,
            groqQuotaRemaining: nil
        )
        XCTAssertEqual(text, "Turbotext ist bereit")
    }

    func testAppendsGroqQuotaWhenGroqReady() {
        let text = MenuBarIdleTooltip.text(
            accessibilityGranted: true,
            inputMonitoringGranted: true,
            cloudIndicator: .groqReady,
            groqQuotaRemaining: "45 Min."
        )
        XCTAssertEqual(text, "Turbotext ist bereit · noch 45 Min. Groq-Kontingent")
    }

    func testWarnsWhenAccessibilityMissing() {
        let text = MenuBarIdleTooltip.text(
            accessibilityGranted: false,
            inputMonitoringGranted: true,
            cloudIndicator: .none,
            groqQuotaRemaining: nil
        )
        XCTAssertEqual(text, "Turbotext eingeschränkt: Bedienungshilfen fehlen")
    }

    func testWarnsWhenInputMonitoringMissing() {
        let text = MenuBarIdleTooltip.text(
            accessibilityGranted: true,
            inputMonitoringGranted: false,
            cloudIndicator: .none,
            groqQuotaRemaining: nil
        )
        XCTAssertEqual(text, "Turbotext eingeschränkt: Tastaturüberwachung fehlt")
    }

    func testWarnsWithBothMissingJoined() {
        let text = MenuBarIdleTooltip.text(
            accessibilityGranted: false,
            inputMonitoringGranted: false,
            cloudIndicator: .none,
            groqQuotaRemaining: nil
        )
        XCTAssertEqual(text, "Turbotext eingeschränkt: Bedienungshilfen fehlen, Tastaturüberwachung fehlt")
    }

    func testPermissionWarningTakesPrecedenceOverQuota() {
        let text = MenuBarIdleTooltip.text(
            accessibilityGranted: false,
            inputMonitoringGranted: true,
            cloudIndicator: .groqReady,
            groqQuotaRemaining: "45 Min."
        )
        XCTAssertEqual(text, "Turbotext eingeschränkt: Bedienungshilfen fehlen")
    }
}
