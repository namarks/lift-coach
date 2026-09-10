import Foundation
import XCTest
@testable import TresFort

final class ProtectedTrainingStoreTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProtectedTrainingStoreTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url.appendingPathComponent("training")
    }

    private func defaults() -> UserDefaults {
        let name = "ProtectedTrainingStoreTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    func testColdReadAndReplacementKeepBackupExclusion() throws {
        let root = try directory()
        let store = ProtectedTrainingStore(directory: root)
        let key = "account-a.workouts"
        for data in [Data("first workout".utf8), Data("updated workout".utf8)] {
            try store.set(data, forKey: key)
            XCTAssertEqual(try ProtectedTrainingStore(directory: root).data(forKey: key), data)
            for url in [root, store.fileURL(forKey: key)] {
                XCTAssertEqual(try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
            }
        }
    }

    func testDeviceFileProtectionSurvivesReplacement() throws {
        let root = try directory()
        let store = ProtectedTrainingStore(directory: root)
        for bytes in [Data([1]), Data([2])] {
            try store.set(bytes, forKey: "training")
            for url in [root, store.fileURL(forKey: "training")] {
                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
#if targetEnvironment(simulator)
                if attributes[.protectionKey] == nil {
                    throw XCTSkip("This simulator does not expose file protection. This test must pass on a physical iPhone before submission.")
                }
#endif
                XCTAssertEqual(attributes[.protectionKey] as? String, FileProtectionType.complete.rawValue)
            }
        }
    }

    func testAccountKeysAndUntrustedNamesCannotEscapeOrCollide() throws {
        let store = ProtectedTrainingStore(directory: try directory())
        let keys = ["account-a.workouts", "account-b.workouts", "../../../workouts"]
        for (index, key) in keys.enumerated() {
            try store.set(Data([UInt8(index)]), forKey: key)
            XCTAssertEqual(store.fileURL(forKey: key).deletingLastPathComponent().path, store.directory.path)
            XCTAssertFalse(store.fileURL(forKey: key).lastPathComponent.contains(key))
        }
        for (index, key) in keys.enumerated() {
            XCTAssertEqual(try store.data(forKey: key), Data([UInt8(index)]))
        }
    }

    func testMigrationPreservesBytesAndRemovesOnlyMigratedPreference() throws {
        let store = ProtectedTrainingStore(directory: try directory())
        let preferences = defaults()
        let data = Data("queued workout with feedback".utf8)
        preferences.set(data, forKey: "account-a")
        preferences.set(Data([2]), forKey: "account-b")
        XCTAssertEqual(try store.data(forKey: "account-a", migratingFrom: preferences), data)
        XCTAssertNil(preferences.data(forKey: "account-a"))
        XCTAssertEqual(preferences.data(forKey: "account-b"), Data([2]))
    }

    func testInterruptedPreferenceFlushCannotReplaceNewerProtectedData() throws {
        let root = try directory()
        let store = ProtectedTrainingStore(directory: root)
        let preferences = defaults()
        try store.set(Data([2]), forKey: "queue")
        preferences.set(Data([1]), forKey: "queue")
        XCTAssertEqual(try ProtectedTrainingStore(directory: root)
            .data(forKey: "queue", migratingFrom: preferences), Data([2]))
        XCTAssertNil(preferences.data(forKey: "queue"))
    }

    func testInterruptedDeletionCannotResurrectLegacyQueue() throws {
        let root = try directory()
        let store = ProtectedTrainingStore(directory: root)
        let preferences = defaults()
        try store.set(Data("private feedback".utf8), forKey: "account-a")
        try store.set(Data([2]), forKey: "account-b")
        try store.removeObject(forKey: "account-a")
        preferences.set(Data("stale preference".utf8), forKey: "account-a")
        let cold = ProtectedTrainingStore(directory: root)
        XCTAssertNil(try cold.data(forKey: "account-a", migratingFrom: preferences))
        XCTAssertNil(preferences.data(forKey: "account-a"))
        XCTAssertEqual(try cold.data(forKey: "account-b"), Data([2]))
        XCTAssertLessThan(try Data(contentsOf: store.fileURL(forKey: "account-a")).count, 10)
    }

    func testFailedMigrationRetainsOriginalAndCleansStagingFile() throws {
        let root = try directory()
        let preferences = defaults()
        preferences.set(Data([1, 2, 3]), forKey: "queue")
        let store = ProtectedTrainingStore(directory: root, replace: { _, _ in
            throw CocoaError(.fileWriteOutOfSpace)
        })
        XCTAssertThrowsError(try store.data(forKey: "queue", migratingFrom: preferences))
        XCTAssertEqual(preferences.data(forKey: "queue"), Data([1, 2, 3]))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [])
    }

    func testFailedReplacementPreservesPreviouslyCommittedValue() throws {
        let root = try directory()
        try ProtectedTrainingStore(directory: root).set(Data([1]), forKey: "queue")
        let store = ProtectedTrainingStore(directory: root, replace: { _, _ in
            throw CocoaError(.fileWriteOutOfSpace)
        })
        XCTAssertThrowsError(try store.set(Data([2]), forKey: "queue"))
        XCTAssertEqual(try ProtectedTrainingStore(directory: root).data(forKey: "queue"), Data([1]))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path).count, 1)
    }

    func testCorruptProtectedFileDoesNotFallBackToStalePreferences() throws {
        let store = ProtectedTrainingStore(directory: try directory())
        let preferences = defaults()
        try store.set(Data([2]), forKey: "queue")
        try Data([255]).write(to: store.fileURL(forKey: "queue"))
        preferences.set(Data([1]), forKey: "queue")
        XCTAssertThrowsError(try store.data(forKey: "queue", migratingFrom: preferences))
        XCTAssertEqual(preferences.data(forKey: "queue"), Data([1]))
    }
}
