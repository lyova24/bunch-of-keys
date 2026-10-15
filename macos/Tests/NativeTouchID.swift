import Foundation
import AppKit
import Security
import SwiftUI

@MainActor final class TestBiometricKeychain: BiometricKeychain {
    var unavailableReason: String?
    var entries: [String: (data: Data, binding: String)] = [:]
    var readError: Error?
    var reads = 0
    var enrollments = 0
    var holdRead = false
    var holdEnrollment = false
    var pendingRead: CheckedContinuation<Data, Error>?
    var pendingEnrollment: CheckedContinuation<Void, Error>?
    func binding(vaultID: String) throws -> String? { entries[vaultID]?.binding }
    func enroll(_ credential: Data, vaultID: String, binding: String, reason: String) async throws {
        if let unavailableReason { throw TouchIDError.unavailable(unavailableReason) }
        enrollments += 1; entries[vaultID] = (credential, binding)
        if holdEnrollment { try await withCheckedThrowingContinuation { pendingEnrollment = $0 } }
    }
    func retrieve(vaultID: String, reason: String) async throws -> Data {
        reads += 1
        if let readError { throw readError }
        if holdRead { return try await withCheckedThrowingContinuation { pendingRead = $0 } }
        guard let entry = entries[vaultID] else { throw TouchIDError.missing }
        return entry.data
    }
    func remove(vaultID: String) throws {
        if var entry = entries.removeValue(forKey: vaultID) { entry.data.resetBytes(in: 0..<entry.data.count) }
    }
    // Intentionally permit a late success: AppStore must reject it independently
    // of whether the native context honors cancellation promptly.
    func cancel() {}
}

@MainActor enum NativeTouchID {
    static func waitFor(_ predicate: () -> Bool) async throws {
        for _ in 0..<200 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        preconditionFailure("Biometric test did not reach the expected state")
    }
    static func run(executable: URL) async throws {
        let keychain = TestBiometricKeychain()
        let board = NSPasteboard(name: .init("dev.keepy.touch-id-tests.\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        let store = AppStore(core: CoreClient(executable: executable), pasteboard: board, biometricKeychain: keychain)
        await store.refresh()
        let created = await store.authenticate(name: "Biometric Native Test", password: "synthetic-biometric-password")
        precondition(created)
        let id = store.vault!.id
        let added = await store.mutate("add_entry", ["name": "Synthetic credential", "fields": [
            ["label": "Password", "kind": "secret", "value": "synthetic-biometric-value", "masked": true]
        ]])
        precondition(added)
        let expected = store.vault
        store.settingsHaveChanges = true
        precondition(!store.canManageTouchID)
        store.settingsHaveChanges = false
        store.manageTouchID()
        await store.enableTouchID(password: "wrong")
        precondition(!store.touchIDEnrolled && keychain.enrollments == 0)
        await store.enableTouchID(password: "synthetic-biometric-password")
        precondition(store.touchIDEnrolled && keychain.entries[id] != nil)
        precondition(store.revealed.isEmpty && board.string(forType: .string) == nil)
        store.cancelTouchIDSetup(); store.lock()
        await store.refreshTouchID()
        await store.unlockWithTouchID()
        precondition(store.vault == expected && keychain.reads == 1)
        precondition(store.vault!.nodes[0].fields![0].value == nil)
        store.lock(); await store.unlockWithTouchID()
        precondition(store.vault == expected && keychain.reads == 2, "Every unlock must retrieve the protected item afresh")

        store.lock(); keychain.readError = TouchIDError.cancelled
        await store.unlockWithTouchID()
        precondition(store.vault == nil && store.touchIDEnrolled && !store.busy)
        keychain.readError = TouchIDError.keychain(errSecAuthFailed)
        await store.unlockWithTouchID()
        precondition(store.vault == nil && store.touchIDMessage != nil)
        keychain.readError = nil
        let fallback = await store.authenticate(password: "synthetic-biometric-password")
        precondition(fallback && store.vault == expected)

        keychain.unavailableReason = "Touch ID unavailable in synthetic test"
        store.lock(); await store.refreshTouchID()
        let readsBefore = keychain.reads
        await store.unlockWithTouchID()
        precondition(store.vault == nil && keychain.reads == readsBefore)
        keychain.unavailableReason = nil; await store.refreshTouchID()

        keychain.holdRead = true
        let lateUnlock = Task { await store.unlockWithTouchID() }
        try await waitFor { keychain.pendingRead != nil }
        store.lock()
        keychain.pendingRead!.resume(returning: keychain.entries[id]!.data); keychain.pendingRead = nil
        await lateUnlock.value
        precondition(store.vault == nil && !store.busy)
        let backend = try CoreClient.decoder.decode(Bootstrap.self, from: await store.core.request("bootstrap"))
        precondition(backend.current == nil, "Late biometric success must not unlock the backend after lock")

        let switchedUnlock = Task { await store.unlockWithTouchID() }
        try await waitFor { keychain.pendingRead != nil }
        store.selectedVaultId = store.vaults.first { $0.id != id }!.id
        keychain.pendingRead!.resume(returning: keychain.entries[id]!.data); keychain.pendingRead = nil
        await switchedUnlock.value
        precondition(store.vault == nil && !store.busy)
        store.selectedVaultId = id; keychain.holdRead = false
        await store.refreshTouchID()

        await store.shutdown()
        let reopened = AppStore(core: CoreClient(executable: executable), pasteboard: board, biometricKeychain: keychain)
        await reopened.refresh(); reopened.selectedVaultId = id
        await reopened.refreshTouchID(); await reopened.unlockWithTouchID()
        precondition(reopened.vault == expected, "Enrollment survives a service/app restart")
        reopened.manageTouchID(); reopened.disableTouchID()
        precondition(!reopened.touchIDEnrolled && keychain.entries[id] == nil)

        keychain.holdEnrollment = true
        let lateEnrollment = Task { await reopened.enableTouchID(password: "synthetic-biometric-password") }
        try await waitFor { keychain.pendingEnrollment != nil }
        reopened.cancelTouchIDSetup()
        keychain.pendingEnrollment!.resume(); keychain.pendingEnrollment = nil
        await lateEnrollment.value
        precondition(keychain.entries[id] == nil && !reopened.touchIDEnrolled && reopened.vault == expected)
        keychain.holdEnrollment = false
        reopened.manageTouchID(); await reopened.enableTouchID(password: "synthetic-biometric-password")
        precondition(reopened.touchIDEnrolled)
        keychain.entries[id]!.binding = "changed-password-wrapping"
        await reopened.refreshTouchID()
        precondition(!reopened.touchIDEnrolled && keychain.entries[id] == nil, "Password rewrapping removes stale enrollment")
        reopened.manageTouchID(); await reopened.enableTouchID(password: "synthetic-biometric-password")
        reopened.lock(); keychain.readError = TouchIDError.missing
        await reopened.unlockWithTouchID()
        precondition(!reopened.touchIDEnrolled && keychain.entries[id] == nil)
        let passwordStillWorks = await reopened.authenticate(password: "synthetic-biometric-password")
        precondition(passwordStillWorks)
        if let directory = ProcessInfo.processInfo.environment["KEEPY_TOUCH_ID_SNAPSHOTS"] {
            try await snapshots(store: reopened, directory: URL(fileURLWithPath: directory))
        }
        reopened.manageTouchID(); await reopened.enableTouchID(password: "synthetic-biometric-password")
        reopened.cancelTouchIDSetup(); reopened.lock()
        keychain.holdRead = true; keychain.readError = nil
        let shutdownUnlock = Task { await reopened.unlockWithTouchID() }
        try await waitFor { keychain.pendingRead != nil }
        await reopened.shutdown()
        keychain.pendingRead!.resume(returning: keychain.entries[id]!.data); keychain.pendingRead = nil
        await shutdownUnlock.value
        precondition(reopened.vault == nil && !reopened.busy, "Late success must not survive shutdown")
        try keychain.remove(vaultID: id)
        print("Native Touch ID passed: enrollment, fresh retrieval, fallback, restart, invalidation, cancellation, vault switch, and late-success rejection (mock Keychain).")
    }

    static func snapshots(store: AppStore, directory: URL) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let savedVault = store.vault
        for (name, scheme, appearance) in [("light", ColorScheme.light, NSAppearance.Name.aqua), ("dark", .dark, .darkAqua)] {
            func capture(_ state: String, _ view: AnyView, height: CGFloat = 380) async throws {
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: height),
                                      styleMask: [.titled], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: appearance)
                window.title = "Synthetic Touch ID preview"
                let host = NSHostingView(rootView: view.frame(width: 480, height: height).background(Color(nsColor: .windowBackgroundColor)).preferredColorScheme(scheme))
                window.contentView = host; window.orderFront(nil)
                defer { window.close() }
                try await Task.sleep(for: .milliseconds(100))
                host.layoutSubtreeIfNeeded()
                guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { preconditionFailure("Snapshot unavailable") }
                host.cacheDisplay(in: host.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("\(state)-\(name).png"))
            }
            store.vault = savedVault; store.touchIDEnrolled = false
            store.touchIDUnavailableReason = nil; store.touchIDMessage = nil
            try await capture("setup", AnyView(TouchIDSettingsView().environmentObject(store)))
            store.touchIDMessage = "The password is incorrect or the vault is damaged."
            try await capture("validation", AnyView(TouchIDSettingsView().environmentObject(store)))
            store.touchIDMessage = nil; store.touchIDEnrolled = true
            try await capture("enabled", AnyView(TouchIDSettingsView().environmentObject(store)))
            store.vault = nil
            try await capture("unlock", AnyView(AuthenticationView(creating: false).environmentObject(store)), height: 560)
            store.touchIDMessage = TouchIDError.cancelled.localizedDescription
            try await capture("cancelled", AnyView(AuthenticationView(creating: false).environmentObject(store)), height: 560)
            store.vault = savedVault; store.touchIDEnrolled = false; store.touchIDMessage = nil
            store.touchIDUnavailableReason = SystemBiometricKeychain.unsupportedBuildMessage
            try await capture("unavailable", AnyView(TouchIDSettingsView().environmentObject(store)))
        }
        store.vault = savedVault; store.touchIDEnrolled = false; store.touchIDMessage = nil
    }
}
