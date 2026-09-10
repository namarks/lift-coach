import Combine
import CryptoKit
import Foundation

/// Preferences keep only small settings and account identifiers. Encoded
/// training, recovery and navigation blobs always use protected local files.
/// The existing keys/formats remain unchanged during migration.
final class LocalPersistence: ObservableObject {
    static let standard = LocalPersistence(
        preferences: .standard,
        trainingStore: ProtectedTrainingStore(directory: baseDirectory.appendingPathComponent("standard")))

    private static var baseDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TresFort/ProtectedLocalState", isDirectory: true)
    }

    let preferences: UserDefaults
    let trainingStore: ProtectedTrainingStore
    private let suiteName: String?
    private enum Failure: Equatable { case read, write, invalidData(Data) }
    private var failures: [String: Failure] = [:]
    private let lock = NSRecursiveLock()
    let objectWillChange = ObservableObjectPublisher()
    private(set) var recoveryGeneration: UInt64 = 0

    init(preferences: UserDefaults, trainingStore: ProtectedTrainingStore, suiteName: String? = nil) {
        self.preferences = preferences
        self.trainingStore = trainingStore
        self.suiteName = suiteName
        // Include inactive accounts and pre-account-scoping blobs. Moving a
        // legacy key does not change which account may subsequently claim it.
        for (key, value) in preferences.dictionaryRepresentation()
            where key.hasPrefix("com.nmarkspdx.liftcoach.") && value is Data {
            _ = data(forKey: key)
        }
    }

    convenience init?(suiteName: String) {
        guard let preferences = UserDefaults(suiteName: suiteName) else { return nil }
        let digest = SHA256.hash(data: Data(suiteName.utf8)).map { String(format: "%02x", $0) }.joined()
        self.init(preferences: preferences,
                  trainingStore: ProtectedTrainingStore(directory: Self.baseDirectory
                    .appendingPathComponent("suites", isDirectory: true).appendingPathComponent(digest)),
                  suiteName: suiteName)
    }

    func data(forKey key: String) -> Data? {
        lock.lock(); defer { lock.unlock() }
        do { return try trainingStore.data(forKey: key, migratingFrom: preferences) }
        catch {
            // A browse cache can be fetched again. Never apply this recovery
            // to queues, feedback, navigation intents or runner checkpoints.
            if isReplaceableCache(key), error is ProtectedTrainingStore.StorageError {
                do {
                    try trainingStore.removeObject(forKey: key, removingLegacyFrom: preferences)
                    return nil
                } catch { }
            }
            record(.read, forKey: key)
            return nil
        }
    }

    func object(forKey key: String) -> Any? {
        if let value = preferences.object(forKey: key), !(value is Data) { return value }
        return data(forKey: key)
    }
    func string(forKey key: String) -> String? { preferences.string(forKey: key) }
    func bool(forKey key: String) -> Bool { preferences.bool(forKey: key) }

    @discardableResult
    func set(_ value: Any?, forKey key: String) -> Bool {
        guard let value else { return removeObject(forKey: key) }
        guard let bytes = value as? Data else {
            preferences.set(value, forKey: key)
            return true
        }
        lock.lock(); defer { lock.unlock() }
        // A read failure must never turn reload-before-mutate into replacing
        // an unreadable queue with a newly constructed empty queue.
        if let failure = failures[key] {
            switch failure {
            case .read, .invalidData: return false
            case .write: break
            }
        }
        do {
            try trainingStore.set(bytes, forKey: key, removingLegacyFrom: preferences)
            clearFailure(forKey: key)
            return true
        } catch {
            record(.write, forKey: key)
            return false
        }
    }

    @discardableResult
    func removeObject(forKey key: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if let failure = failures[key] {
            switch failure {
            case .read, .invalidData: return false
            case .write: break
            }
        }
        return eraseObject(forKey: key)
    }

    /// Only acknowledged account deletion may erase unreadable durable data.
    @discardableResult
    func eraseAfterAccountDeletion(forKey key: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return eraseObject(forKey: key)
    }

    private func eraseObject(forKey key: String) -> Bool {
        if let value = preferences.object(forKey: key), !(value is Data) {
            preferences.removeObject(forKey: key)
            return true
        }
        do {
            try trainingStore.removeObject(forKey: key, removingLegacyFrom: preferences)
            clearFailure(forKey: key)
            return true
        } catch {
            record(.write, forKey: key)
            return false
        }
    }

    func recordInvalidData(_ data: Data, forKey key: String) {
        lock.lock(); defer { lock.unlock() }
        record(.invalidData(data), forKey: key)
    }

    func recordWriteFailure(forKey key: String) {
        lock.lock(); defer { lock.unlock() }
        record(.write, forKey: key)
    }

    func hasFailure(forKey key: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return failures[key] != nil
    }

    func hasFailure(userID: String?) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return failures.keys.contains { belongsToAccount($0, userID: userID) }
    }

    /// Retry reads/migration and prove a protected write is possible before
    /// reopening the UI. Corrupt durable intents remain intact for recovery;
    /// a retry cannot silently discard their bytes.
    @discardableResult
    func retry(userID: String?) -> Bool {
        lock.lock(); defer { lock.unlock() }
        let selected = failures.filter { belongsToAccount($0.key, userID: userID) }
        guard !selected.isEmpty else { return true }
        for (key, failure) in selected {
            do {
                let current = try trainingStore.data(forKey: key, migratingFrom: preferences)
                if case .invalidData(let unreadable) = failure, current == unreadable { continue }
                try trainingStore.set(Data(), forKey: "storage-write-probe")
                try trainingStore.removeObject(forKey: "storage-write-probe")
                clearFailure(forKey: key)
            } catch { continue }
        }
        guard !hasFailure(userID: userID) else { return false }
        publishChange()
        recoveryGeneration &+= 1
        return true
    }

    /// Named synthetic/test namespaces own both their preferences and files.
    /// Never permit one namespace to erase another namespace's directory.
    func removePersistentDomain(forName name: String) {
        precondition(suiteName == name)
        preferences.removePersistentDomain(forName: name)
        try? FileManager.default.removeItem(at: trainingStore.directory)
        lock.lock(); defer { lock.unlock() }
        failures.removeAll()
    }

    private func isReplaceableCache(_ key: String) -> Bool {
        key.hasPrefix("com.nmarkspdx.liftcoach.state-snapshot.")
            || key.hasPrefix("com.nmarkspdx.liftcoach.exercise-catalog-snapshot.")
    }

    private func belongsToAccount(_ key: String, userID: String?) -> Bool {
        if key == "com.nmarkspdx.liftcoach.pending-entry.v1" { return true }
        let legacyKeys: Set<String> = [
            "com.nmarkspdx.liftcoach.activity-outbox.v1",
            "com.nmarkspdx.liftcoach.intervals-connection.v1",
            "com.nmarkspdx.liftcoach.healthkit-anchor.v1",
        ]
        if legacyKeys.contains(key) {
            return userID.map { AccountLocalState.legacyStateBelongs(to: $0, defaults: self) } ?? true
        }
        return userID.map { key.hasSuffix("." + $0) } == true
    }

    private func record(_ failure: Failure, forKey key: String) {
        guard failures[key] != failure else { return }
        failures[key] = failure
        publishChange()
    }

    private func clearFailure(forKey key: String) {
        if failures.removeValue(forKey: key) != nil { publishChange() }
    }

    private func publishChange() {
        // Store reads may happen while a view is being constructed. Defer
        // notification to avoid publishing recursively during that update.
        DispatchQueue.main.async { [weak self] in self?.objectWillChange.send() }
    }
}
