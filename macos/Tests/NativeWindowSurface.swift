import AppKit
import SwiftUI

@MainActor private final class SurfaceSettings: ObservableObject {
    @Published var glass = false
    @Published var reduceTransparency = false
}
private struct SurfaceProbe: View {
    @ObservedObject var settings: SurfaceSettings
    var body: some View {
        Text("Synthetic window test").frame(maxWidth: .infinity, maxHeight: .infinity)
            .modifier(WindowSurfaceAppearance(enabled: settings.glass, reduceTransparency: settings.reduceTransparency))
    }
}
@MainActor enum NativeWindowSurface {
    static func run() async throws {
        guard #available(macOS 26, *) else { return }
        _ = NSApplication.shared
        let settings = SurfaceSettings()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 620), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SurfaceProbe(settings: settings))
        defer { window.close() }
        func surface(in view: NSView) -> WindowSurfaceView? {
            if let surface = view as? WindowSurfaceView { return surface }
            return view.subviews.lazy.compactMap { surface(in: $0) }.first
        }
        func waitFor(_ predicate: () -> Bool) async throws {
            for _ in 0..<100 {
                window.contentView?.layoutSubtreeIfNeeded()
                if predicate() { return }
                try await Task.sleep(for: .milliseconds(20))
            }
            preconditionFailure("Window surface did not update")
        }
        try await waitFor { surface(in: window.contentView!) != nil }
        let bridge = surface(in: window.contentView!)!
        precondition(window.isOpaque && !window.titlebarAppearsTransparent)
        settings.glass = true
        try await waitFor { !window.isOpaque && bridge.material?.isHidden == false }
        precondition(window.backgroundColor.alphaComponent == 0 && window.titlebarAppearsTransparent)
        precondition(bridge.material?.superview === window.contentView?.superview)
        precondition(bridge.material?.blendingMode == .behindWindow)
        window.setContentSize(NSSize(width: 720, height: 700))
        window.contentView?.layoutSubtreeIfNeeded()
        precondition(bridge.material?.frame == window.contentView?.superview?.bounds, "Material must cover the entire resized window")
        settings.reduceTransparency = true
        try await waitFor { window.isOpaque && bridge.material?.isHidden == true }
        precondition(window.backgroundColor.alphaComponent == 1 && !window.titlebarAppearsTransparent)
        settings.reduceTransparency = false
        try await waitFor { !window.isOpaque }
        settings.glass = false
        try await waitFor { window.isOpaque && bridge.material?.isHidden == true }
        print("Native window surface passed: whole-window material, resize, settings changes and Reduce Transparency.")
    }
}
