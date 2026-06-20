import Foundation

/// Pure decision logic for the dismissible main-window hint banner shown when
/// Input Monitoring isn't granted yet (breaks keyCode-based hotkeys silently).
enum InputMonitoringHintBanner {
    static func shouldShow(inputMonitoringGranted: Bool, dismissed: Bool) -> Bool {
        !inputMonitoringGranted && !dismissed
    }
}
