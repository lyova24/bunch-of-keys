import SwiftUI
import AppKit

struct WindowSurface: ViewModifier {
    var enabled: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        content.modifier(WindowSurfaceAppearance(enabled: enabled, reduceTransparency: reduceTransparency))
    }
}
struct WindowSurfaceAppearance: ViewModifier {
    var enabled: Bool
    var reduceTransparency: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            let glass = enabled && !reduceTransparency
            content.containerBackground(glass ? Color.clear : Color(nsColor: .windowBackgroundColor), for: .window)
            .toolbarBackgroundVisibility(glass ? .hidden : .automatic, for: .windowToolbar)
            .background(WindowSurfaceConfiguration(transparent: glass).frame(width: 0, height: 0))
        } else {
            content
        }
    }
}

struct WindowSurfaceConfiguration: NSViewRepresentable {
    var transparent: Bool
    func makeNSView(context: Context) -> WindowSurfaceView { WindowSurfaceView() }
    func updateNSView(_ view: WindowSurfaceView, context: Context) {
        view.transparent = transparent
        view.applyAppearance()
    }
    static func dismantleNSView(_ view: WindowSurfaceView, coordinator: ()) { view.detach() }
}

final class WindowSurfaceView: NSView {
    var transparent = false
    private weak var configuredWindow: NSWindow?
    private var originalFullSizeContent = false
    private(set) var material: NSVisualEffectView?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyAppearance()
    }
    func applyAppearance() {
        guard let window, let content = window.contentView else { return }
        if configuredWindow !== window {
            detach()
            configuredWindow = window
            originalFullSizeContent = window.styleMask.contains(.fullSizeContentView)
        }
        window.isOpaque = !transparent
        window.backgroundColor = transparent ? .clear : .windowBackgroundColor
        window.titlebarAppearsTransparent = transparent
        window.titlebarSeparatorStyle = transparent ? .none : .automatic
        if transparent {
            window.styleMask.insert(.fullSizeContentView)
            guard let frame = content.superview else { return }
            if material?.superview !== frame {
                material?.removeFromSuperview()
                let background = NSVisualEffectView(frame: frame.bounds)
                // Keep the material in the native window hierarchy. Rendering it
                // inside a SwiftUI glass effect prevents behind-window sampling.
                background.blendingMode = .behindWindow
                background.material = .underWindowBackground
                background.state = .followsWindowActiveState
                background.autoresizingMask = [.width, .height]
                frame.addSubview(background, positioned: .below, relativeTo: content)
                material = background
            }
            material?.frame = frame.bounds
            material?.isHidden = false
        } else {
            material?.isHidden = true
            if !originalFullSizeContent { window.styleMask.remove(.fullSizeContentView) }
        }
    }
    func detach() {
        material?.removeFromSuperview()
        material = nil
        if let window = configuredWindow {
            window.isOpaque = true
            window.backgroundColor = .windowBackgroundColor
            window.titlebarAppearsTransparent = false
            window.titlebarSeparatorStyle = .automatic
            if !originalFullSizeContent { window.styleMask.remove(.fullSizeContentView) }
        }
        configuredWindow = nil
    }
}
