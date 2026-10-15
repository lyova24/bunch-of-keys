import CryptoKit
import Foundation

func reject(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

// Verify with the public key embedded in the shipped app, independently of
// the publisher's Keychain. Never publish metadata for a different signing key.
final class Enclosure: NSObject, XMLParserDelegate {
    let filename: String
    var signature: String?
    init(filename: String) { self.filename = filename }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes: [String: String]) {
        if elementName == "enclosure", let url = attributes["url"], URL(string: url)?.lastPathComponent == filename {
            signature = attributes["sparkle:edSignature"]
        }
    }
}
let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])), format: nil) as! [String: Any]
let key = try Curve25519.Signing.PublicKey(rawRepresentation: Data(base64Encoded: plist["SUPublicEDKey"] as! String)!)
let feed = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))
let footer = String(decoding: feed, as: UTF8.self).components(separatedBy: "<!-- sparkle-signatures:").last!
let fields = Dictionary(uniqueKeysWithValues: footer.split(separator: "\n").compactMap { line -> (String, String)? in
    let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
    return parts.count == 2 ? (parts[0], parts[1]) : nil
})
guard let encoded = fields["edSignature"], let signature = Data(base64Encoded: encoded),
      let count = fields["length"].flatMap(Int.init), count > 0, count < feed.count,
      key.isValidSignature(signature, for: feed.prefix(count)) else {
    reject("Feed signature does not match the app's public key")
}
let archiveURL = URL(fileURLWithPath: CommandLine.arguments[3])
let enclosure = Enclosure(filename: archiveURL.lastPathComponent)
let parser = XMLParser(data: feed); parser.delegate = enclosure
guard parser.parse(), let encodedArchiveSignature = enclosure.signature,
      let archiveSignature = Data(base64Encoded: encodedArchiveSignature),
      key.isValidSignature(archiveSignature, for: try Data(contentsOf: archiveURL)) else {
    reject("Archive signature does not match the app's public key")
}
print("Feed and archive signatures match the public key in the shipped app.")
