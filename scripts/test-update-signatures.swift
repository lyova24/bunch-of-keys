import CryptoKit
import Foundation

// Ephemeral test material only: never use these keys for published updates.
let directory = URL(fileURLWithPath: CommandLine.arguments[1])
let key = Curve25519.Signing.PrivateKey()
try key.rawRepresentation.base64EncodedString().write(to: directory.appendingPathComponent("test-key"), atomically: true, encoding: .utf8)
let archive = Data("synthetic update archive for signature verification".utf8)
try archive.write(to: directory.appendingPathComponent("valid.zip"))
try (archive + Data("modified".utf8)).write(to: directory.appendingPathComponent("tampered.zip"))
try archive.prefix(12).write(to: directory.appendingPathComponent("interrupted.zip"))

let app = directory.appendingPathComponent("Probe.app")
try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
try Data("#!/bin/sh\nexit 0\n".utf8).write(to: app.appendingPathComponent("Contents/MacOS/probe"))
let info: [String: Any] = [
    "CFBundleIdentifier": "dev.keepy.update-test." + UUID().uuidString,
    "CFBundleName": "Keepy Update Test", "CFBundleExecutable": "probe", "CFBundlePackageType": "APPL",
    "CFBundleVersion": "2.2.0", "CFBundleShortVersionString": "2.2.0",
    "SUPublicEDKey": key.publicKey.rawRepresentation.base64EncodedString(),
    "SUEnableAutomaticChecks": false, "SUAllowsAutomaticUpdates": false,
    "SURequireSignedFeed": true, "SUVerifyUpdateBeforeExtraction": true,
    "NSAppTransportSecurity": ["NSAllowsLocalNetworking": true]
]
try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
    .write(to: app.appendingPathComponent("Contents/Info.plist"))
for (name, version, minimum) in [("new", "2.2.1", "14.0"), ("old", "2.1.1", "14.0"), ("future-os", "2.2.1", "99.0")] {
    let xml = """
    <?xml version="1.0" encoding="utf-8"?>
    <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><title>Test updates</title><item><title>Keepy \(version)</title><sparkle:version>\(version)</sparkle:version><sparkle:minimumSystemVersion>\(minimum)</sparkle:minimumSystemVersion><enclosure url="https://example.com/valid.zip" length="\(archive.count)" type="application/octet-stream" sparkle:edSignature="\(try key.signature(for: archive).base64EncodedString())"/></item></channel></rss>
    """
    try xml.write(to: directory.appendingPathComponent(name + ".xml"), atomically: true, encoding: .utf8)
}
try Data("unsigned and invalid XML".utf8).write(to: directory.appendingPathComponent("invalid.xml"))
