import CryptoKit
import Darwin
import Foundation

/// Synchronous storage for training blobs. Replacements are prepared inside
/// the backup-excluded directory and atomically renamed. Complete file
/// protection makes the data available only while unlocked. Callers must
/// surface errors before claiming a local intent was saved or sending a
/// mutation that depends on that intent.
final class ProtectedTrainingStore {
    enum StorageError: Error { case invalidEnvelope }
    private enum Value { case absent, deleted, data(Data) }
    private static let header = Data("TFT1\0".utf8)
    let directory: URL
    private let lock: NSRecursiveLock
    private let replace: (URL, URL) throws -> Void

    private final class WeakLock {
        weak var value: NSRecursiveLock?
        init(_ value: NSRecursiveLock) { self.value = value }
    }
    private static let registryLock = NSLock()
    private static var locks: [String: WeakLock] = [:]

    init(directory: URL,
         replace: @escaping (URL, URL) throws -> Void = ProtectedTrainingStore.atomicReplace) {
        self.directory = directory.standardizedFileURL
        self.replace = replace
        Self.registryLock.lock()
        defer { Self.registryLock.unlock() }
        Self.locks = Self.locks.filter { $0.value.value != nil }
        let key = self.directory.path
        let shared = Self.locks[key]?.value ?? NSRecursiveLock()
        Self.locks[key] = WeakLock(shared)
        lock = shared
    }

    static func atomicReplace(_ temporary: URL, _ destination: URL) throws {
        guard Darwin.rename(temporary.path, destination.path) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
    }

    /// Existing versioned/account-scoped keys remain the identity boundary.
    /// Account IDs, workout titles and untrusted paths never become filenames.
    func fileURL(forKey key: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8))
            .map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(digest + ".bin")
    }

    func data(forKey key: String) throws -> Data? {
        lock.lock(); defer { lock.unlock() }
        switch try value(forKey: key) {
        case .absent, .deleted: return nil
        case .data(let data): return data
        }
    }

    /// A protected copy is authoritative even if an interrupted preferences
    /// flush leaves legacy bytes behind. Failed migration keeps those bytes
    /// untouched and reports an error, never an empty queue.
    func data(forKey key: String, migratingFrom defaults: UserDefaults) throws -> Data? {
        lock.lock(); defer { lock.unlock() }
        switch try value(forKey: key) {
        case .data(let data):
            defaults.removeObject(forKey: key)
            return data
        case .deleted:
            defaults.removeObject(forKey: key)
            return nil
        case .absent:
            guard let legacy = defaults.data(forKey: key) else { return nil }
            try persist(legacy, forKey: key)
            defaults.removeObject(forKey: key)
            return legacy
        }
    }

    func set(_ data: Data, forKey key: String, removingLegacyFrom defaults: UserDefaults? = nil) throws {
        lock.lock(); defer { lock.unlock() }
        try persist(data, forKey: key)
        defaults?.removeObject(forKey: key)
    }

    /// Commit a tiny tombstone before removing the preferences value. Simply
    /// unlinking the file could resurrect an old queue after a process dies
    /// before UserDefaults flushes its removal. The tombstone retains no
    /// workout bytes; it remains under the hashed key on this installation.
    func removeObject(forKey key: String, removingLegacyFrom defaults: UserDefaults? = nil) throws {
        lock.lock(); defer { lock.unlock() }
        try persist(nil, forKey: key)
        defaults?.removeObject(forKey: key)
    }

    private func value(forKey key: String) throws -> Value {
        let bytes: Data
        do { bytes = try Data(contentsOf: fileURL(forKey: key)) }
        catch CocoaError.fileReadNoSuchFile { return .absent }
        guard bytes.starts(with: Self.header), bytes.count > Self.header.count else {
            throw StorageError.invalidEnvelope
        }
        switch bytes[Self.header.count] {
        case 0 where bytes.count == Self.header.count + 1: return .deleted
        case 1: return .data(Data(bytes.dropFirst(Self.header.count + 1)))
        default: throw StorageError.invalidEnvelope
        }
    }

    private func persist(_ data: Data?, forKey key: String) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true,
                                    attributes: [.protectionKey: FileProtectionType.complete])
        try manager.setAttributes([.protectionKey: FileProtectionType.complete],
                                  ofItemAtPath: directory.path)
        try excludeFromBackup(directory)
        let temporary = directory.appendingPathComponent("write-" + UUID().uuidString)
        defer { try? manager.removeItem(at: temporary) }

        // Protect and exclude an empty staging file before putting training
        // bytes in it. Rename preserves those file attributes.
        try Data().write(to: temporary, options: .completeFileProtection)
        try excludeFromBackup(temporary)
        let handle = try FileHandle(forWritingTo: temporary)
        do {
            var bytes = Self.header
            bytes.append(data == nil ? 0 : 1)
            if let data { bytes.append(data) }
            try handle.write(contentsOf: bytes)
            try handle.synchronize()
            try handle.close()
        } catch {
            try? handle.close()
            throw error
        }
        try replace(temporary, fileURL(forKey: key))
    }

    private func excludeFromBackup(_ url: URL) throws {
        var mutableURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try mutableURL.setResourceValues(values)
    }
}
