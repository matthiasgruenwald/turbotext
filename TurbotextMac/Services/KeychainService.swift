import Foundation
import Security

enum KeychainKey: String, CaseIterable, Codable {
    case groqAPIKey = "groqAPIKey"
    case openAIAPIKey = "openAIAPIKey"

    var label: String {
        switch self {
        case .groqAPIKey: return "Groq API Key"
        case .openAIAPIKey: return "OpenAI API Key"
        }
    }
}

/// Stores preview credentials in the user's macOS Keychain.
enum KeychainService {
    private static let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    private static let service = isRunningTests
        ? "app.turbotext.preview.credentials.tests"
        : "app.turbotext.preview.credentials"

    static func save(key: KeychainKey, value: String) throws {
        let data = Data(value.utf8)
        var query = baseQuery(for: key)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(query as CFDictionary, nil)

        if status == errSecDuplicateItem {
            let updateStatus = SecItemUpdate(
                baseQuery(for: key) as CFDictionary,
                [kSecValueData as String: data] as CFDictionary
            )
            guard updateStatus == errSecSuccess else {
                throw KeychainError.saveFailed(updateStatus)
            }
            return
        }

        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    static func load(key: KeychainKey) -> String? {
        var query = baseQuery(for: key)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty else {
            return nil
        }

        return value
    }

    static func delete(key: KeychainKey) {
        SecItemDelete(baseQuery(for: key) as CFDictionary)
    }

    static var isConfigured: Bool {
        load(key: .openAIAPIKey) != nil
    }

    private static func baseQuery(for key: KeychainKey) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]
    }
}

enum KeychainError: LocalizedError {
    case saveFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            return "Zugangsdaten konnten nicht im macOS Keychain gespeichert werden. Status: \(status)"
        }
    }
}
