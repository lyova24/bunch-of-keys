import AppKit
import Foundation

// Render the shipping raster and SVG from the same path used by the native UI.
@main struct RenderLogo {
    static func main() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let size = 1024
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let graphics = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        let context = graphics.cgContext
        context.translateBy(x: 0, y: CGFloat(size))
        context.scaleBy(x: 1, y: -1)
        context.setShouldAntialias(true)
        let tile = CGPath(roundedRect: CGRect(x: 72, y: 72, width: 880, height: 880),
                          cornerWidth: 196, cornerHeight: 196, transform: nil)
        context.saveGState()
        context.addPath(tile); context.clip()
        let colors = [CGColor(gray: 0.99, alpha: 1), CGColor(gray: 0.90, alpha: 1)]
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1])!
        context.drawLinearGradient(gradient, start: CGPoint(x: 200, y: 72), end: CGPoint(x: 824, y: 952), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        context.restoreGState()
        context.addPath(tile); context.setStrokeColor(CGColor(gray: 0.7, alpha: 0.24)); context.setLineWidth(2); context.strokePath()
        context.saveGState()
        for (index, path) in AppLogo.paths(in: CGRect(x: 206, y: 164, width: 612, height: 696)).enumerated() {
            context.setFillColor(AppLogo.color(for: index))
            context.addPath(path); context.drawPath(using: .eoFill)
        }
        context.restoreGState()
        NSGraphicsContext.restoreGraphicsState()
        try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("icon.png"))
        let paths = AppLogo.paths.enumerated().map { index, path in
            "  <path fill=\"\(index == 2 ? "#6b9cc4" : "#78b842")\" fill-rule=\"evenodd\" d=\"\(svgPath(path))\"/>"
        }.joined(separator: "\n")
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="-8 -12 120 118" role="img" aria-labelledby="title">
          <title id="title">Keepy bunch of keys logo</title>
        \(paths)
        </svg>

        """
        try svg.write(to: output.appendingPathComponent("logo.svg"), atomically: true, encoding: .utf8)
        let letters = AppLogo.wordmarkPaths.enumerated().map { index, path in
            "  <path fill=\"\(index == 5 ? "#6b9cc4" : "#78b842")\" d=\"\(svgPath(path))\"/>"
        }.joined(separator: "\n")
        let wordmark = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="60 20 785 275" role="img" aria-labelledby="title">
          <title id="title">Keepy</title>
        \(letters)
        </svg>

        """
        try wordmark.write(to: output.appendingPathComponent("wordmark.svg"), atomically: true, encoding: .utf8)
    }
    static func svgPath(_ path: CGPath) -> String {
        func point(_ value: CGPoint) -> String { String(format: "%.4f %.4f", locale: Locale(identifier: "en_US_POSIX"), Double(value.x), Double(value.y)) }
        var commands: [String] = []
        path.applyWithBlock { pointer in
            let element = pointer.pointee
            switch element.type {
            case .moveToPoint: commands.append("M\(point(element.points[0]))")
            case .addLineToPoint: commands.append("L\(point(element.points[0]))")
            case .addQuadCurveToPoint: commands.append("Q\(point(element.points[0])) \(point(element.points[1]))")
            case .addCurveToPoint: commands.append("C\(point(element.points[0])) \(point(element.points[1])) \(point(element.points[2]))")
            case .closeSubpath: commands.append("Z")
            @unknown default: break
            }
        }
        return commands.joined(separator: " ")
    }
}
