import XCTest
@testable import Turbotext

final class PermissionGuideTests: XCTestCase {

    // MARK: - Deep links

    func testAccessibilityDeepLinkPointsAtAccessibilityPrivacyPane() {
        XCTAssertEqual(
            PermissionGuideStep.accessibility.settingsDeepLink.absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        )
    }

    func testInputMonitoringDeepLinkPointsAtListenEventPrivacyPane() {
        XCTAssertEqual(
            PermissionGuideStep.inputMonitoring.settingsDeepLink.absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        )
    }

    // MARK: - Planner

    func testPlanRequestsBothStepsInCanonicalOrderWhenNothingGranted() {
        let steps = PermissionGuidePlanner.planSteps(
            requested: [.accessibility, .inputMonitoring],
            accessibilityGranted: false,
            inputMonitoringGranted: false
        )
        XCTAssertEqual(steps, [.accessibility, .inputMonitoring])
    }

    func testPlanSkipsAlreadyGrantedAccessibility() {
        let steps = PermissionGuidePlanner.planSteps(
            requested: [.accessibility, .inputMonitoring],
            accessibilityGranted: true,
            inputMonitoringGranted: false
        )
        XCTAssertEqual(steps, [.inputMonitoring])
    }

    func testPlanSkipsAlreadyGrantedInputMonitoring() {
        let steps = PermissionGuidePlanner.planSteps(
            requested: [.accessibility, .inputMonitoring],
            accessibilityGranted: false,
            inputMonitoringGranted: true
        )
        XCTAssertEqual(steps, [.accessibility])
    }

    func testPlanIsEmptyWhenEverythingRequestedIsAlreadyGranted() {
        let steps = PermissionGuidePlanner.planSteps(
            requested: [.accessibility, .inputMonitoring],
            accessibilityGranted: true,
            inputMonitoringGranted: true
        )
        XCTAssertEqual(steps, [])
    }

    func testPlanHonoursSingleStepRequest() {
        let steps = PermissionGuidePlanner.planSteps(
            requested: [.inputMonitoring],
            accessibilityGranted: false,
            inputMonitoringGranted: false
        )
        XCTAssertEqual(steps, [.inputMonitoring])
    }

    // MARK: - Monitor decision

    func testMonitorReportsGrantedFirst() {
        let outcome = PermissionGuideMonitor.evaluate(permissionGranted: true, settingsVisible: false)
        XCTAssertEqual(outcome, .permissionGranted)
    }

    func testMonitorReportsClosedWhenSettingsMissing() {
        let outcome = PermissionGuideMonitor.evaluate(permissionGranted: false, settingsVisible: false)
        XCTAssertEqual(outcome, .settingsClosed)
    }

    func testMonitorKeepsWatchingWhileSettingsVisible() {
        let outcome = PermissionGuideMonitor.evaluate(permissionGranted: false, settingsVisible: true)
        XCTAssertEqual(outcome, .keepWatching)
    }

    func testAbortTriggersAtThreshold() {
        XCTAssertTrue(PermissionGuideMonitor.shouldAbort(consecutiveSettingsClosed: 3))
        XCTAssertFalse(PermissionGuideMonitor.shouldAbort(consecutiveSettingsClosed: 2))
    }

    // MARK: - System Settings window lookup

    private func window(ownerPid: pid_t, layer: Int, x: Double, y: Double, width: Double, height: Double) -> [String: Any] {
        [
            kCGWindowOwnerPID as String: ownerPid,
            kCGWindowLayer as String: layer,
            kCGWindowBounds as String: ["X": x, "Y": y, "Width": width, "Height": height]
        ]
    }

    func testWindowFinderPicksLayerZeroWindowOfSettingsBundle() {
        let windows: [[String: Any]] = [
            window(ownerPid: 99, layer: 0, x: 100, y: 80, width: 770, height: 560),
            window(ownerPid: 42, layer: 0, x: 0, y: 0, width: 300, height: 200)
        ]
        let frame = SystemSettingsWindowFinder.frame(in: windows) { pid in
            pid == 99 ? SystemSettingsWindowFinder.settingsBundleIdentifier : "com.apple.finder"
        }
        XCTAssertEqual(frame, CGRect(x: 100, y: 80, width: 770, height: 560))
    }

    func testWindowFinderIgnoresNonZeroLayers() {
        let windows: [[String: Any]] = [
            window(ownerPid: 99, layer: 1, x: 100, y: 80, width: 770, height: 560)
        ]
        let frame = SystemSettingsWindowFinder.frame(in: windows) { _ in
            SystemSettingsWindowFinder.settingsBundleIdentifier
        }
        XCTAssertNil(frame)
    }

    func testWindowFinderReturnsNilWithoutSettingsWindow() {
        let windows: [[String: Any]] = [
            window(ownerPid: 42, layer: 0, x: 0, y: 0, width: 300, height: 200)
        ]
        let frame = SystemSettingsWindowFinder.frame(in: windows) { _ in "com.apple.finder" }
        XCTAssertNil(frame)
    }

    // MARK: - Drag source URL

    func testDragSourceUsesRunningBundleWhenItExists() {
        let bundle = URL(fileURLWithPath: "/Applications/Turbotext.app")
        let fallback = URL(fileURLWithPath: "/Applications/Turbotext Copy.app")
        let url = PermissionGuideDragSource.url(bundleURL: bundle, applicationsFallback: fallback) { _ in true }
        XCTAssertEqual(url, bundle)
    }

    func testDragSourceFallsBackWhenRunningBundleMissing() {
        let bundle = URL(fileURLWithPath: "/private/tmp/build/Turbotext.app")
        let fallback = URL(fileURLWithPath: "/Applications/Turbotext.app")
        let url = PermissionGuideDragSource.url(bundleURL: bundle, applicationsFallback: fallback) { path in
            path == fallback.path
        }
        XCTAssertEqual(url, fallback)
    }

    // MARK: - Panel positioning

    func testCGFrameConversionFlipsYAxisAgainstPrimaryScreenHeight() {
        let appKit = PermissionGuidePanelPositioning.appKitFrame(
            fromCGFrame: CGRect(x: 100, y: 120, width: 770, height: 560),
            primaryScreenHeight: 1080
        )
        XCTAssertEqual(appKit, CGRect(x: 100, y: 400, width: 770, height: 560))
    }

    func testOriginPrefersRightSideOfSettingsWindow() {
        let settings = CGRect(x: 100, y: 300, width: 770, height: 560)
        let screen = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        let panelSize = CGSize(width: 300, height: 220)

        let origin = PermissionGuidePanelPositioning.origin(
            settingsFrame: settings,
            panelSize: panelSize,
            screenFrame: screen
        )

        XCTAssertEqual(origin.x, settings.maxX + PermissionGuidePanelPositioning.margin)
        XCTAssertEqual(origin.y, settings.midY - panelSize.height / 2)
    }

    func testOriginFlipsToLeftWhenRightSideIsOffScreen() {
        let settings = CGRect(x: 1200, y: 300, width: 770, height: 560)
        let screen = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        let panelSize = CGSize(width: 300, height: 220)

        let origin = PermissionGuidePanelPositioning.origin(
            settingsFrame: settings,
            panelSize: panelSize,
            screenFrame: screen
        )

        XCTAssertEqual(origin.x, settings.minX - PermissionGuidePanelPositioning.margin - panelSize.width)
    }

    func testOriginClampsIntoScreenBounds() {
        let settings = CGRect(x: 10, y: 10, width: 770, height: 560)
        let screen = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        let panelSize = CGSize(width: 300, height: 220)

        let origin = PermissionGuidePanelPositioning.origin(
            settingsFrame: settings,
            panelSize: panelSize,
            screenFrame: screen
        )

        XCTAssertGreaterThanOrEqual(origin.y, screen.minY)
        XCTAssertLessThanOrEqual(origin.y + panelSize.height, screen.maxY)
    }

    func testOriginFallsBackToTopRightWithoutSettingsFrame() {
        let screen = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        let panelSize = CGSize(width: 300, height: 220)

        let origin = PermissionGuidePanelPositioning.origin(
            settingsFrame: nil,
            panelSize: panelSize,
            screenFrame: screen
        )

        XCTAssertEqual(origin.x, screen.maxX - PermissionGuidePanelPositioning.margin - panelSize.width)
        XCTAssertEqual(origin.y, screen.maxY - PermissionGuidePanelPositioning.margin - panelSize.height)
    }
}
