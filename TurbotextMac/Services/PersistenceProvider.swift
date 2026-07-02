import Foundation

/// Seam over key-value persistence so stores can be tested without touching real UserDefaults.
protocol PersistenceProvider: AnyObject {
    func string(forKey key: String) -> String?
    func data(forKey key: String) -> Data?
    func bool(forKey key: String) -> Bool
    func object(forKey key: String) -> Any?
    func integer(forKey key: String) -> Int
    func double(forKey key: String) -> Double
    func stringArray(forKey key: String) -> [String]?

    func set(_ value: String?, forKey key: String)
    func set(_ value: Data?, forKey key: String)
    func set(_ value: Bool, forKey key: String)
    func set(_ value: Int, forKey key: String)
    func set(_ value: Double, forKey key: String)
    func set(_ value: [String], forKey key: String)

    func removeObject(forKey key: String)
}

/// Production adapter: delegates to `UserDefaults.standard`.
final class UserDefaultsPersistence: PersistenceProvider {
    static let shared = UserDefaultsPersistence()

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func string(forKey key: String) -> String? { defaults.string(forKey: key) }
    func data(forKey key: String) -> Data? { defaults.data(forKey: key) }
    func bool(forKey key: String) -> Bool { defaults.bool(forKey: key) }
    func object(forKey key: String) -> Any? { defaults.object(forKey: key) }
    func integer(forKey key: String) -> Int { defaults.integer(forKey: key) }
    func double(forKey key: String) -> Double { defaults.double(forKey: key) }
    func stringArray(forKey key: String) -> [String]? { defaults.stringArray(forKey: key) }

    func set(_ value: String?, forKey key: String) { defaults.set(value, forKey: key) }
    func set(_ value: Data?, forKey key: String) { defaults.set(value, forKey: key) }
    func set(_ value: Bool, forKey key: String) { defaults.set(value, forKey: key) }
    func set(_ value: Int, forKey key: String) { defaults.set(value, forKey: key) }
    func set(_ value: Double, forKey key: String) { defaults.set(value, forKey: key) }
    func set(_ value: [String], forKey key: String) { defaults.set(value, forKey: key) }

    func removeObject(forKey key: String) { defaults.removeObject(forKey: key) }
}

/// In-memory adapter for tests: no shared state, no cross-test pollution.
final class InMemoryPersistence: PersistenceProvider {
    private var storage: [String: Any] = [:]

    func string(forKey key: String) -> String? { storage[key] as? String }
    func data(forKey key: String) -> Data? { storage[key] as? Data }
    func bool(forKey key: String) -> Bool { storage[key] as? Bool ?? false }
    func object(forKey key: String) -> Any? { storage[key] }
    func integer(forKey key: String) -> Int { storage[key] as? Int ?? 0 }
    func double(forKey key: String) -> Double { storage[key] as? Double ?? 0 }
    func stringArray(forKey key: String) -> [String]? { storage[key] as? [String] }

    func set(_ value: String?, forKey key: String) { storage[key] = value }
    func set(_ value: Data?, forKey key: String) { storage[key] = value }
    func set(_ value: Bool, forKey key: String) { storage[key] = value }
    func set(_ value: Int, forKey key: String) { storage[key] = value }
    func set(_ value: Double, forKey key: String) { storage[key] = value }
    func set(_ value: [String], forKey key: String) { storage[key] = value }

    func removeObject(forKey key: String) { storage.removeValue(forKey: key) }
}
