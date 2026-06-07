import SwiftUI
import AppKit

struct ShortcutRecorderView: View {
    let onRecord: (Shortcut) -> Void

    @State private var isRecording = false
    @State private var globalMonitor: Any?
    @State private var localMonitor: Any?
    @State private var lastNonEmptyFlags: NSEvent.ModifierFlags = []

    var body: some View {
        Button(isRecording ? "Drücken…" : "+ Hinzufügen") {
            if isRecording {
                stopRecording()
            } else {
                startRecording()
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(isRecording ? .orange : .blue)
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        isRecording = true
        lastNonEmptyFlags = []

        // Brief delay so the button-click event isn't captured as a shortcut.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            installMonitors()
        }
    }

    private func installMonitors() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            Task { @MainActor in captureEvent(event) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            Task { @MainActor in captureEvent(event) }
            return nil  // Swallow so event isn't dispatched to other handlers during recording.
        }
    }

    private func captureEvent(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        switch event.type {
        case .keyDown:
            let shortcut = Shortcut(modifiers: flags, keyCode: event.keyCode)
            stopRecording()
            onRecord(shortcut)

        case .flagsChanged:
            if !flags.isEmpty {
                lastNonEmptyFlags = flags
            } else if !lastNonEmptyFlags.isEmpty {
                let shortcut = Shortcut(modifiers: lastNonEmptyFlags, keyCode: nil)
                stopRecording()
                onRecord(shortcut)
            }

        default:
            break
        }
    }

    private func stopRecording() {
        if let m = globalMonitor { NSEvent.removeMonitor(m) }
        if let m = localMonitor  { NSEvent.removeMonitor(m) }
        globalMonitor = nil
        localMonitor = nil
        isRecording = false
        lastNonEmptyFlags = []
    }
}
