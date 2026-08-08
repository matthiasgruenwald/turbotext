import AppKit
import OSLog

private let relaunchLogger = Logger(subsystem: "app.turbotext.mac", category: "LiveDictation")

/// Relaunches Turbotext as a fresh process and terminates the current one. The only known
/// recovery from a poisoned Apple Speech XPC connection (#191 follow-up): once a process's
/// connection to `com.apple.speech.localspeechrecognition` breaks — observed after standby —
/// every later call fails fast with "Failed to connect with remote process", forever, even
/// after the system daemon itself is healthy again. A fresh process gets a fresh XPC
/// bootstrap and just works, matching what manually quitting and reopening the app does.
enum AppSelfRelauncher {
    @MainActor
    static func relaunch() {
        relaunchLogger.error("self-relaunching after persistent Apple Speech securing failures")
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            if let error {
                relaunchLogger.error("self-relaunch failed to open a new instance: \(error.localizedDescription, privacy: .public)")
            }
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }
}
