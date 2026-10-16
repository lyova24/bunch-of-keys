import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var updates: UpdateController
    @State private var draft = Preferences()
    @State private var saving = false
    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Appearance") {
                    Picker("Theme", selection: $draft.appearance) {
                        Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark")
                    }
                    if #available(macOS 26, *) { Toggle("Liquid Glass", isOn: $draft.liquidGlass) }
                    else { Text("Liquid Glass is available on macOS 26 and later.").font(.caption).foregroundStyle(.secondary) }
                }
                Section("Security") {
                    Stepper("Lock after \(draft.autoLockSeconds / 60) minutes of inactivity", value: $draft.autoLockSeconds, in: 60...86400, step: 60)
                    Stepper("Clear clipboard after \(draft.clipboardClearSeconds) seconds", value: $draft.clipboardClearSeconds, in: 5...3600, step: 5)
                    Text("Vaults also lock when the Mac sleeps, the display sleeps, or your login session becomes inactive.").font(.caption).foregroundStyle(.secondary)
                }
                TrayShortcutSection()
                Section("Startup") {
                    Toggle("Launch at login", isOn: $draft.autostart)
                    if SMAppService.mainApp.status == .requiresApproval {
                        Button("Allow in Login Items Settings…") { SMAppService.openSystemSettingsLoginItems() }
                    }
                }
                Section("Updates") {
                    Toggle("Automatically check for updates", isOn: Binding(
                        get: { updates.automaticallyChecks }, set: { updates.setAutomaticallyChecks($0) }
                    )).disabled(updates.configurationError != nil)
                    Button("Check for Updates…") { updates.check() }.disabled(!updates.canCheck)
                    if let error = updates.configurationError {
                        Text(error).font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Updates are downloaded and installed only with your approval.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                EditorError()
            }.formStyle(.grouped).scrollContentBackground(.hidden)
            Divider()
            HStack {
                Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development")").font(.caption).foregroundStyle(.secondary); Spacer()
                if saving { ProgressView().controlSize(.small) }
                Button("Save") { saving = true; Task { _ = await store.saveSettings(draft); saving = false } }.disabled(draft == store.settings || saving || !store.serviceAvailable)
            }.padding(16)
        }.frame(width: 500, height: 600)
            .onAppear { draft = store.settings; store.error = nil }
            .onChange(of: draft) { _, value in store.settingsHaveChanges = value != store.settings }
            .onChange(of: store.settings) { _, value in store.settingsHaveChanges = draft != value }
            .onDisappear { store.settingsHaveChanges = false }
    }
}
