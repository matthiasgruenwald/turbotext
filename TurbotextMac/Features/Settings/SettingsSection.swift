import Foundation

enum SettingsSection: Int, CaseIterable, Identifiable {
    case transcription
    case workflows
    case shortcuts
    case credentials
    case appManagement

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .transcription: return "Transkription"
        case .workflows: return "Workflows"
        case .shortcuts: return "Tastenkürzel"
        case .credentials: return "Zugangsdaten"
        case .appManagement: return "App-Verwaltung"
        }
    }

    var iconName: String {
        switch self {
        case .transcription: return "waveform"
        case .workflows: return "wand.and.stars"
        case .shortcuts: return "keyboard"
        case .credentials: return "key.fill"
        case .appManagement: return "gearshape.2"
        }
    }

    static func defaultSection(accessibilityPermissionGranted: Bool) -> SettingsSection {
        accessibilityPermissionGranted ? .transcription : .credentials
    }
}
