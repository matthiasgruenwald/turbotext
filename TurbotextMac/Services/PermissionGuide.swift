import AppKit

enum PermissionGuideStep: Equatable, Hashable {
    case accessibility
    case inputMonitoring

    var settingsDeepLink: URL {
        switch self {
        case .accessibility:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        case .inputMonitoring:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
        }
    }

    @MainActor
    var isGranted: Bool {
        switch self {
        case .accessibility:
            return AccessibilityPermissionService.currentStatus()
        case .inputMonitoring:
            return InputMonitoringPermissionService.currentStatus()
        }
    }
}

enum PermissionGuidePlanner {
    static func planSteps(
        requested: Set<PermissionGuideStep>,
        accessibilityGranted: Bool,
        inputMonitoringGranted: Bool
    ) -> [PermissionGuideStep] {
        var steps: [PermissionGuideStep] = []
        if requested.contains(.accessibility), !accessibilityGranted {
            steps.append(.accessibility)
        }
        if requested.contains(.inputMonitoring), !inputMonitoringGranted {
            steps.append(.inputMonitoring)
        }
        return steps
    }
}

enum PermissionGuideMonitor {
    enum Outcome: Equatable {
        case permissionGranted
        case settingsClosed
        case keepWatching
    }

    static func evaluate(permissionGranted: Bool, settingsVisible: Bool) -> Outcome {
        if permissionGranted { return .permissionGranted }
        if !settingsVisible { return .settingsClosed }
        return .keepWatching
    }

    static func shouldAbort(consecutiveSettingsClosed: Int) -> Bool {
        consecutiveSettingsClosed >= 3
    }
}

enum SystemSettingsWindowFinder {
    static let settingsBundleIdentifier = "com.apple.systempreferences"

    static func frame(in windows: [[String: Any]], ownerBundleIdentifier: (pid_t) -> String?) -> CGRect? {
        for window in windows {
            guard let pidNumber = window[kCGWindowOwnerPID as String] as? NSNumber else { continue }
            let pid = pid_t(pidNumber.intValue)
            guard ownerBundleIdentifier(pid) == settingsBundleIdentifier else { continue }
            guard let layerNumber = window[kCGWindowLayer as String] as? NSNumber, layerNumber.intValue == 0 else { continue }
            guard let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let x = (bounds["X"] as? NSNumber)?.doubleValue,
                  let y = (bounds["Y"] as? NSNumber)?.doubleValue,
                  let width = (bounds["Width"] as? NSNumber)?.doubleValue,
                  let height = (bounds["Height"] as? NSNumber)?.doubleValue,
                  width > 0, height > 0 else { continue }
            return CGRect(x: x, y: y, width: width, height: height)
        }
        return nil
    }

    static func currentFrame() -> CGRect? {
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return nil }
        return frame(in: windows) { pid in
            NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
        }
    }
}

enum PermissionGuideDragSource {
    static func url(
        bundleURL: URL = TurbotextInstallLocationService.bundleURL,
        applicationsFallback: URL = TurbotextInstallLocationService.systemApplicationsDirectoryURL
            .appendingPathComponent(TurbotextInstallLocationService.bundleURL.lastPathComponent),
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> URL {
        fileExists(bundleURL.path) ? bundleURL : applicationsFallback
    }
}

enum PermissionGuidePanelPositioning {
    static let margin: CGFloat = 16

    static func appKitFrame(fromCGFrame cgFrame: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(
            x: cgFrame.origin.x,
            y: primaryScreenHeight - cgFrame.origin.y - cgFrame.height,
            width: cgFrame.width,
            height: cgFrame.height
        )
    }

    static func origin(settingsFrame: CGRect?, panelSize: CGSize, screenFrame: CGRect?) -> CGPoint {
        guard let screenFrame else { return .zero }
        guard let settingsFrame else {
            return CGPoint(
                x: screenFrame.maxX - margin - panelSize.width,
                y: screenFrame.maxY - margin - panelSize.height
            )
        }

        var x = settingsFrame.maxX + margin
        if x + panelSize.width > screenFrame.maxX {
            x = settingsFrame.minX - margin - panelSize.width
        }
        var y = settingsFrame.midY - panelSize.height / 2

        x = min(max(x, screenFrame.minX), screenFrame.maxX - panelSize.width)
        y = min(max(y, screenFrame.minY), screenFrame.maxY - panelSize.height)
        return CGPoint(x: x, y: y)
    }
}
