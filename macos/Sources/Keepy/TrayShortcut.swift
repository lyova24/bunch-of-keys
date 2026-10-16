import AppKit
import Carbon
import SwiftUI

struct TrayShortcut: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    var key: String
    static let `default` = TrayShortcut(keyCode: UInt32(kVK_F8), modifiers: UInt32(cmdKey), key: "F8")
    static let modifierMask = UInt32(cmdKey | controlKey | optionKey | shiftKey)
    var isValid: Bool {
        keyCode < 128 && ![54, 55, 56, 57, 58, 59, 60, 61, 62, 63].contains(keyCode) &&
        modifiers & ~Self.modifierMask == 0 && modifiers & UInt32(cmdKey | controlKey | optionKey) != 0 &&
        !key.isEmpty && key.count <= 20
    }
    var title: String {
        [(controlKey, "⌃"), (optionKey, "⌥"), (shiftKey, "⇧"), (cmdKey, "⌘")]
            .filter { modifiers & UInt32($0.0) != 0 }.map(\.1).joined() + key
    }
    init(keyCode: UInt32, modifiers: UInt32, key: String) {
        self.keyCode = keyCode; self.modifiers = modifiers; self.key = key
    }
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        let special: [UInt16: String] = [36: "Return", 48: "Tab", 49: "Space", 51: "Delete", 53: "Escape",
            76: "Enter", 115: "Home", 116: "Page Up", 117: "Forward Delete", 119: "End", 121: "Page Down",
            123: "←", 124: "→", 125: "↓", 126: "↑"]
        let functionKeys: [UInt16] = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106, 64, 79, 80, 90]
        let key: String
        if let index = functionKeys.firstIndex(of: event.keyCode) { key = "F\(index + 1)" }
        else if let name = special[event.keyCode] { key = name }
        else {
            guard let characters = event.characters(byApplyingModifiers: []),
                  !characters.isEmpty, characters.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else { return nil }
            key = characters.uppercased()
        }
        self.init(keyCode: UInt32(event.keyCode), modifiers: modifiers, key: key)
        if !isValid { return nil }
    }
}

/// Owns one exclusive Carbon registration. Replacing it first reserves the new
/// combination, so a conflict never destroys the existing working shortcut.
@MainActor final class GlobalTrayHotKey {
    private var handler: EventHandlerRef?
    private var hotKey: EventHotKeyRef?
    private var sequence: UInt32 = 0
    private static var nextID: UInt32 = 0
    var eventID: EventHotKeyID { EventHotKeyID(signature: Self.signature, id: sequence) }
    private(set) var shortcut: TrayShortcut?
    var action: (() -> Void)?
    private static let signature: OSType = 0x4B707954 // KpyT

    init() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr else { return status }
            let owner = Unmanaged<GlobalTrayHotKey>.fromOpaque(context).takeUnretainedValue()
            let matches = MainActor.assumeIsolated {
                owner.hotKey != nil && id.signature == GlobalTrayHotKey.signature && id.id == owner.sequence
            }
            guard matches else { return OSStatus(eventNotHandledErr) }
            // Leave the Carbon callback before entering AppKit menu tracking.
            DispatchQueue.main.async { [weak owner] in
                guard let owner, owner.hotKey != nil, id.signature == GlobalTrayHotKey.signature, id.id == owner.sequence else { return }
                owner.action?()
            }
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }
    @discardableResult func replace(with shortcut: TrayShortcut?) -> OSStatus {
        guard let shortcut else { unregister(); return noErr }
        guard shortcut.isValid, handler != nil else { return OSStatus(paramErr) }
        if self.shortcut == shortcut { return noErr }
        Self.nextID &+= 1
        let next = Self.nextID
        var candidate: EventHotKeyRef?
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers,
            EventHotKeyID(signature: Self.signature, id: next), GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &candidate)
        guard status == noErr else { return status }
        unregister()
        hotKey = candidate; sequence = next; self.shortcut = shortcut
        return noErr
    }
    private func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil; shortcut = nil
    }
    func stop() {
        unregister()
        if let handler { RemoveEventHandler(handler) }
        handler = nil; action = nil
    }
    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
}

@MainActor final class TrayShortcutSettings: ObservableObject {
    private struct Preference: Codable {
        var enabled = true
        var shortcut = TrayShortcut.default
    }
    @Published private(set) var showFullCredentialNames: Bool
    @Published private(set) var enabled: Bool
    @Published private(set) var shortcut: TrayShortcut
    @Published private(set) var error: String?
    @Published private(set) var recording = false
    private let defaults: UserDefaults
    private let preferenceKey = "trayMenuShortcut"
    let hotKey = GlobalTrayHotKey()
    private var started = false

    init(defaults: UserDefaults? = nil) {
        // Isolated UI/test runs must not overwrite the real app's preferences.
        self.defaults = defaults ?? ProcessInfo.processInfo.environment["KEEPY_DATA_DIR"]
            .map { UserDefaults(suiteName: "dev.keepy.shortcut.\(Data($0.utf8).base64EncodedString())")! } ?? .standard
        let value = self.defaults.data(forKey: preferenceKey).flatMap { try? JSONDecoder().decode(Preference.self, from: $0) }
        let preference = value.flatMap { $0.shortcut.isValid ? $0 : nil } ?? Preference()
        showFullCredentialNames = self.defaults.bool(forKey: "trayShowFullCredentialNames")
        enabled = preference.enabled; shortcut = preference.shortcut
    }
    func setShowFullCredentialNames(_ value: Bool) {
        showFullCredentialNames = value
        defaults.set(value, forKey: "trayShowFullCredentialNames")
    }
    func start(action: @escaping () -> Void) {
        guard !started else { return }
        started = true; hotKey.action = action
        applyCurrent()
    }
    private func applyCurrent() {
        let status = hotKey.replace(with: enabled && !recording ? shortcut : nil)
        error = status == noErr ? nil : "Could not register \(shortcut.title). It may be in use by macOS or another app. Choose another shortcut or disable it."
    }
    @discardableResult func set(enabled: Bool, shortcut: TrayShortcut) -> Bool {
        guard shortcut.isValid else { return false }
        let status = hotKey.replace(with: enabled ? shortcut : nil)
        guard status == noErr else {
            error = "\(shortcut.title) is unavailable. Choose another shortcut. Your previous setting is unchanged."
            return false
        }
        self.enabled = enabled; self.shortcut = shortcut; error = nil
        defaults.set(try? JSONEncoder().encode(Preference(enabled: enabled, shortcut: shortcut)), forKey: preferenceKey)
        return true
    }
    func beginRecording() {
        recording = true; error = nil
        hotKey.replace(with: nil)
    }
    func endRecording() {
        guard recording else { return }
        recording = false
        let previousError = error
        applyCurrent()
        if let previousError { error = previousError }
    }
    func stop() { recording = false; started = false; hotKey.stop() }
}

struct TrayShortcutSection: View {
    @EnvironmentObject var shortcuts: TrayShortcutSettings
    var body: some View {
        Section("Keyboard Shortcuts") {
            Toggle("Open menu bar menu", isOn: Binding(get: { shortcuts.enabled }, set: {
                _ = shortcuts.set(enabled: $0, shortcut: shortcuts.shortcut)
            }))
            HStack {
                Text("Shortcut")
                Spacer()
                ShortcutRecorder(settings: shortcuts).frame(width: 160, height: 26)
                    .disabled(!shortcuts.enabled)
                Button("Reset") { _ = shortcuts.set(enabled: true, shortcut: .default) }
                    .disabled(shortcuts.recording || (shortcuts.enabled && shortcuts.shortcut == .default))
            }
            Text("Changes apply immediately. Click the shortcut, then press a key with Control, Option or Command. Escape cancels. For F-keys, you may need to hold Fn.")
                .font(.caption).foregroundStyle(.secondary)
            if let error = shortcuts.error { Text(error).font(.caption).foregroundStyle(.red).accessibilityLabel(error) }
        }.onDisappear { shortcuts.endRecording() }
    }
}

struct ShortcutRecorder: NSViewRepresentable {
    @ObservedObject var settings: TrayShortcutSettings
    func makeNSView(context: Context) -> ShortcutRecorderButton { ShortcutRecorderButton() }
    func updateNSView(_ button: ShortcutRecorderButton, context: Context) {
        button.settings = settings
        button.title = settings.recording ? "Press shortcut…" : settings.shortcut.title
        button.isEnabled = settings.enabled
        button.setAccessibilityLabel("Record menu bar shortcut")
        button.setAccessibilityValue(button.title)
    }
    static func dismantleNSView(_ button: ShortcutRecorderButton, coordinator: ()) { button.finish() }
}

@MainActor final class ShortcutRecorderButton: NSButton {
    weak var settings: TrayShortcutSettings?
    private var monitor: Any?
    private var focusObserver: NSObjectProtocol?
    override init(frame: NSRect) {
        super.init(frame: frame)
        bezelStyle = .rounded; target = self; action = #selector(begin)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc func begin() {
        guard monitor == nil, let settings else { return }
        window?.makeFirstResponder(self)
        settings.beginRecording(); title = "Press shortcut…"
        focusObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.finish() }
        }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.window?.isKeyWindow == true else { return event }
            if event.isARepeat { return nil }
            let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
            if event.keyCode == 53 && flags.isEmpty { self.finish(); return nil }
            if event.keyCode == 48 && flags.isEmpty { self.finish(); return event }
            guard let shortcut = TrayShortcut(event: event) else { NSSound.beep(); return nil }
            _ = settings.set(enabled: true, shortcut: shortcut)
            self.finish()
            return nil
        }
    }
    override func resignFirstResponder() -> Bool { finish(); return super.resignFirstResponder() }
    override func viewWillMove(toWindow newWindow: NSWindow?) { if newWindow == nil { finish() }; super.viewWillMove(toWindow: newWindow) }
    func finish() {
        guard monitor != nil || focusObserver != nil else { return }
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if let focusObserver { NotificationCenter.default.removeObserver(focusObserver) }
        focusObserver = nil
        settings?.endRecording()
        if let settings { title = settings.shortcut.title }
    }
}
