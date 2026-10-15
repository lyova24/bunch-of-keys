import Foundation
import LocalAuthentication
import Security
import SwiftUI

@MainActor protocol BiometricKeychain: AnyObject {
    var unavailableReason: String? { get }
    func binding(vaultID: String) throws -> String?
    func enroll(_ credential: Data, vaultID: String, binding: String, reason: String) async throws
    func retrieve(vaultID: String, reason: String) async throws -> Data
    func remove(vaultID: String) throws
    func cancel()
}

enum TouchIDError: LocalizedError {
    case cancelled, missing, unavailable(String), keychain(OSStatus)
    var errorDescription: String? {
        switch self {
        case .cancelled: return "Touch ID was cancelled. You can unlock with the master password."
        case .missing: return "Touch ID enrollment is no longer valid. Unlock with the master password and set up Touch ID again."
        case .unavailable(let message): return message
        case .keychain(let status):
            if status == errSecMissingEntitlement {
                return "This build cannot access the protected Keychain. Use the master password and install a build provisioned for Touch ID."
            }
            return "The protected Keychain could not be accessed (\(status)). Use the master password; you can set up Touch ID again from the Vault menu."
        }
    }
}

// No file-based Keychain or device-password fallback: the item itself requires
// the currently enrolled biometrics, independent of our UI's availability check.
@MainActor final class SystemBiometricKeychain: BiometricKeychain {
    static let unsupportedBuildMessage = "Touch ID is unavailable in this build. Ad-hoc builds do not support Touch ID. Use your master password to unlock."
    private let service = "\(Bundle.main.bundleIdentifier ?? "dev.keepy.desktop").touch-id.v1"
    private var context: LAContext?

    static var signingAvailable: Bool {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var information: CFDictionary?
        guard Bundle.main.url(forResource: "embedded", withExtension: "provisionprofile") != nil,
              SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let values = information as? [String: Any],
              let team = values[kSecCodeInfoTeamIdentifier as String] as? String, !team.isEmpty,
              let entitlements = values[kSecCodeInfoEntitlementsDict as String] as? [String: Any],
              let application = entitlements["com.apple.application-identifier"] as? String,
              application == "\(team).\(Bundle.main.bundleIdentifier ?? "")" else { return false }
        return true
    }

    var unavailableReason: String? {
        guard Self.signingAvailable else {
            return Self.unsupportedBuildMessage
        }
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error),
              context.biometryType == .touchID else {
            if (error as? LAError)?.code == .biometryLockout {
                return "Touch ID is locked by macOS. Unlock with the master password, or restore Touch ID availability in macOS."
            }
            return "Touch ID is unavailable. Check Touch ID enrollment in macOS Settings, or use the master password."
        }
        return nil
    }

    private func query(_ vaultID: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: vaultID,
         kSecUseDataProtectionKeychain as String: true,
         kSecAttrSynchronizable as String: false]
    }

    func binding(vaultID: String) throws -> String? {
        guard Self.signingAvailable else { return nil }
        var query = query(vaultID)
        let context = LAContext(); context.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = context
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw TouchIDError.keychain(status) }
        guard let attributes = result as? [String: Any],
              let data = attributes[kSecAttrGeneric as String] as? Data,
              let binding = String(data: data, encoding: .utf8) else { throw TouchIDError.missing }
        return binding
    }

    private func newContext(_ reason: String) -> LAContext {
        cancel()
        let context = LAContext()
        context.localizedReason = reason
        context.localizedFallbackTitle = ""
        context.touchIDAuthenticationAllowableReuseDuration = 0
        self.context = context
        return context
    }

    private func read(vaultID: String, context: LAContext) async throws -> Data {
        var query = query(vaultID)
        query[kSecUseAuthenticationContext as String] = context
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var result: CFTypeRef?
                let status = SecItemCopyMatching(query as CFDictionary, &result)
                if status == errSecUserCanceled { continuation.resume(throwing: TouchIDError.cancelled) }
                else if status == errSecItemNotFound { continuation.resume(throwing: TouchIDError.missing) }
                else if status != errSecSuccess { continuation.resume(throwing: TouchIDError.keychain(status)) }
                else if let data = result as? Data, data.count <= 4096 { continuation.resume(returning: data) }
                else { continuation.resume(throwing: TouchIDError.missing) }
            }
        }
    }

    func enroll(_ credential: Data, vaultID: String, binding: String, reason: String) async throws {
        if let reason = unavailableReason { throw TouchIDError.unavailable(reason) }
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                                                         .biometryCurrentSet, &error) else {
            throw TouchIDError.unavailable("macOS could not protect this enrollment with Touch ID.")
        }
        let context = newContext(reason)
        defer { context.invalidate(); self.context = nil }
        var query = query(vaultID)
        query[kSecAttrAccessControl as String] = access
        query[kSecAttrGeneric as String] = Data(binding.utf8)
        query[kSecAttrLabel as String] = "Keepy Touch ID"
        query[kSecValueData as String] = credential
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw TouchIDError.keychain(status) }
        do {
            // Enrollment is complete only after a real ACL-protected retrieval.
            var verified = try await read(vaultID: vaultID, context: context)
            defer { verified.resetBytes(in: 0..<verified.count) }
            guard verified == credential else { throw TouchIDError.missing }
        } catch {
            try remove(vaultID: vaultID)
            throw error
        }
    }

    func retrieve(vaultID: String, reason: String) async throws -> Data {
        if let reason = unavailableReason { throw TouchIDError.unavailable(reason) }
        let context = newContext(reason)
        defer { context.invalidate(); self.context = nil }
        return try await read(vaultID: vaultID, context: context)
    }

    func remove(vaultID: String) throws {
        let status = SecItemDelete(query(vaultID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw TouchIDError.keychain(status) }
    }

    func cancel() { context?.invalidate(); context = nil }
}

struct TouchIDSettingsView: View {
    @EnvironmentObject var store: AppStore
    @State private var password = ""
    @FocusState private var passwordFocused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Touch ID", systemImage: "touchid").font(.title2.weight(.semibold)).help(store.touchIDHelp)
                Spacer()
                if let reason = store.touchIDUnavailableReason {
                    Image(systemName: "info.circle").foregroundStyle(.secondary)
                        .help(reason).accessibilityLabel("Touch ID unavailable")
                }
            }
            Text(store.vaultName).font(.headline)
            Text("Use Touch ID to unlock this vault on this Mac. Your master password remains available and is not stored.")
            if let reason = store.touchIDUnavailableReason {
                Text(reason).foregroundStyle(.secondary)
            }
            if store.touchIDEnrolled {
                Label("Touch ID is enabled for this vault", systemImage: "checkmark.circle")
                Button("Disable Touch ID", role: .destructive) { store.disableTouchID() }.disabled(store.busy)
            } else if store.touchIDUnavailableReason == nil {
                SecureField("Current master password", text: $password).textFieldStyle(.roundedBorder).focused($passwordFocused)
                Text("Confirm your master password, then approve the macOS Touch ID prompt.").font(.caption).foregroundStyle(.secondary)
            }
            if let error = store.touchIDMessage { Text(error).font(.callout).foregroundStyle(.secondary).textSelection(.enabled) }
            HStack {
                Button(store.touchIDInProgress ? "Cancel" : "Done") { password = ""; store.cancelTouchIDSetup() }.keyboardShortcut(.cancelAction)
                Spacer()
                if store.touchIDInProgress { ProgressView().controlSize(.small) }
                if !store.touchIDEnrolled && store.touchIDUnavailableReason == nil {
                    Button("Enable Touch ID") {
                        let input = password; password = ""
                        Task { await store.enableTouchID(password: input) }
                    }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(password.isEmpty || store.busy)
                }
            }
        }.padding(24).frame(width: 390)
            .onAppear { passwordFocused = true }
            .onDisappear { password = "" }
            .onChange(of: store.vault?.id) { _, _ in password = "" }
    }
}
