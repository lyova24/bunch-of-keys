import Foundation
import Sparkle

@MainActor enum NativeUpdates {
    static func run() {
        precondition(UpdatePolicy.feedURL(architecture: "arm64").hasSuffix("/appcast-arm64.xml"))
        precondition(UpdatePolicy.feedURL(architecture: "x86_64").hasSuffix("/appcast-x86_64.xml"))
        let comparator = SUStandardVersionComparator.default
        precondition(comparator.compareVersion("2.2.1", toVersion: "2.2.0") == .orderedDescending)
        precondition(comparator.compareVersion("2.2.0", toVersion: "2.2.0") == .orderedSame)
        precondition(comparator.compareVersion("2.1.1", toVersion: "2.2.0") == .orderedAscending)
        precondition(comparator.compareVersion("2.10.0", toVersion: "2.9.9") == .orderedDescending)
        precondition(!UpdatePolicy.blocksRestart(busy: false, editor: false, keys: false, prompt: false, settings: false))
        for flag in 0..<5 {
            precondition(UpdatePolicy.blocksRestart(busy: flag == 0, editor: flag == 1, keys: flag == 2,
                                                   prompt: flag == 3, settings: flag == 4))
        }
        print("Native updates passed: separate architecture feeds, Sparkle version ordering and restart guards.")
    }
}
