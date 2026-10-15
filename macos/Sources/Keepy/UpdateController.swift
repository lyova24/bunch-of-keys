import AppKit
import Combine
import Sparkle

enum UpdatePolicy {
    static func feedURL(architecture: String) -> String {
        "https://github.com/lyova24/keepy/releases/latest/download/appcast-\(architecture).xml"
    }
    static var architecture: String {
        #if arch(arm64)
        "arm64"
        #else
        "x86_64"
        #endif
    }
    static func blocksRestart(busy: Bool, editor: Bool, keys: Bool, prompt: Bool, settings: Bool) -> Bool {
        busy || editor || keys || prompt || settings
    }
}

/// Sparkle owns downloading, signature validation, atomic replacement and recovery.
/// Keep one controller alive for the whole process, including when windows close.
@MainActor final class UpdateController: NSObject, ObservableObject, SPUUpdaterDelegate {
    @Published private(set) var canCheck = false
    @Published private(set) var automaticallyChecks = false
    @Published private(set) var configurationError: String?
    private var controller: SPUStandardUpdaterController!
    private var observations: [NSKeyValueObservation] = []

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
        observations = [
            controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
                Task { @MainActor in self?.canCheck = updater.canCheckForUpdates }
            },
            controller.updater.observe(\.automaticallyChecksForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
                Task { @MainActor in self?.automaticallyChecks = updater.automaticallyChecksForUpdates }
            }
        ]
    }
    func start() {
        // Never weaken authentication for ad-hoc builds or isolated test runs.
        guard ProcessInfo.processInfo.environment["KEEPY_DATA_DIR"] == nil else { return }
        guard let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              Data(base64Encoded: key)?.count == 32 else {
            configurationError = "This build has no update signing key. Install a release build to enable updates."
            canCheck = false
            return
        }
        do { try controller.updater.start() }
        catch { configurationError = error.localizedDescription; canCheck = false }
    }
    func check() { controller.checkForUpdates(nil) }
    func setAutomaticallyChecks(_ enabled: Bool) {
        controller.updater.automaticallyChecksForUpdates = enabled
    }
    func feedURLString(for updater: SPUUpdater) -> String? {
        UpdatePolicy.feedURL(architecture: UpdatePolicy.architecture)
    }
}
