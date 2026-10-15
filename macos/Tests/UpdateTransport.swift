import AppKit
import Sparkle

@MainActor final class Probe: NSObject, SPUUpdaterDelegate {
    var feed: String
    var found: String?
    var failure: Error?
    var finished = false
    init(_ feed: String) { self.feed = feed }
    func feedURLString(for updater: SPUUpdater) -> String? { feed }
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) { found = item.versionString }
    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        failure = error; finished = true
    }
}

@main struct UpdateTransport {
    @MainActor static func main() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let bundle = Bundle(url: URL(fileURLWithPath: CommandLine.arguments[1]))!
        let root = CommandLine.arguments[2]
        let delegate = Probe(root + "/new.xml")
        let driver = SPUStandardUserDriver(hostBundle: bundle, delegate: nil)
        let updater = SPUUpdater(hostBundle: bundle, applicationBundle: bundle, userDriver: driver, delegate: delegate)
        updater.automaticallyChecksForUpdates = false
        updater.automaticallyDownloadsUpdates = false
        try updater.start()
        for (feed, expected) in [("new.xml", "2.2.1"), ("old.xml", nil), ("future-os.xml", nil), ("invalid.xml", nil), ("offline", nil)] {
            delegate.feed = feed == "offline" ? "http://127.0.0.1:1/appcast.xml" : root + "/" + feed
            delegate.finished = false; delegate.found = nil; delegate.failure = nil
            precondition(!updater.automaticallyChecksForUpdates)
            updater.checkForUpdateInformation()
            for _ in 0..<400 {
                if delegate.finished { break }
                try await Task.sleep(for: .milliseconds(50))
            }
            precondition(delegate.finished, "Update check timed out: \(feed)")
            precondition(delegate.found == expected, "Incorrect update selection for \(feed): \(delegate.found ?? "none")")
            if feed == "invalid.xml" || feed == "offline" {
                precondition(delegate.failure != nil, "Invalid feed/offline check must fail")
            }
        }
        print("Sparkle transport passed: manual probes with automatic checks disabled, newer release, no downgrade, OS requirements, invalid feed and offline failure.")
    }
}
