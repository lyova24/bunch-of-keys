import AppKit
import SwiftUI

// One vector composition supplies every Keepy logo representation.
enum AppLogo {
    static let name = "Keepy"
    static let green = CGColor(red: 0.47, green: 0.72, blue: 0.26, alpha: 1)
    static let blue = CGColor(red: 0.42, green: 0.61, blue: 0.77, alpha: 1)
    static func color(for index: Int) -> CGColor { index == 2 ? blue : green }

    // Geometric lettering inspired by the supplied wordmark; outlines need no font.
    static var wordmarkPaths: [CGPath] {
        func stroke(_ draw: (CGMutablePath) -> Void) -> CGPath {
            let path = CGMutablePath()
            draw(path)
            return path.copy(strokingWithWidth: 13, lineCap: .butt, lineJoin: .miter, miterLimit: 4)
        }
        let k = stroke { p in
            p.move(to: CGPoint(x: 88, y: 37)); p.addLine(to: CGPoint(x: 88, y: 224))
            p.move(to: CGPoint(x: 205, y: 37)); p.addLine(to: CGPoint(x: 88, y: 148))
            p.move(to: CGPoint(x: 114, y: 124)); p.addLine(to: CGPoint(x: 223, y: 224))
        }
        let e = stroke { p in
            p.move(to: CGPoint(x: 355, y: 166))
            p.addCurve(to: CGPoint(x: 287, y: 220), control1: CGPoint(x: 351, y: 202), control2: CGPoint(x: 328, y: 220))
            p.addCurve(to: CGPoint(x: 220, y: 151), control1: CGPoint(x: 244, y: 220), control2: CGPoint(x: 220, y: 195))
            p.addCurve(to: CGPoint(x: 287, y: 81), control1: CGPoint(x: 220, y: 107), control2: CGPoint(x: 243, y: 81))
            p.addCurve(to: CGPoint(x: 356, y: 144), control1: CGPoint(x: 332, y: 81), control2: CGPoint(x: 356, y: 107))
            p.addLine(to: CGPoint(x: 220, y: 144))
        }
        var shift = CGAffineTransform(translationX: 162, y: 0)
        let p = stroke { p in
            p.move(to: CGPoint(x: 543, y: 77)); p.addLine(to: CGPoint(x: 543, y: 277))
            p.move(to: CGPoint(x: 543, y: 151))
            p.addCurve(to: CGPoint(x: 611, y: 81), control1: CGPoint(x: 543, y: 107), control2: CGPoint(x: 567, y: 81))
            p.addCurve(to: CGPoint(x: 679, y: 151), control1: CGPoint(x: 656, y: 81), control2: CGPoint(x: 679, y: 107))
            p.addCurve(to: CGPoint(x: 611, y: 220), control1: CGPoint(x: 679, y: 195), control2: CGPoint(x: 656, y: 220))
            p.addCurve(to: CGPoint(x: 543, y: 151), control1: CGPoint(x: 567, y: 220), control2: CGPoint(x: 543, y: 195))
        }
        let leftY = stroke { p in
            p.move(to: CGPoint(x: 683, y: 77)); p.addLine(to: CGPoint(x: 743, y: 223))
        }
        let rightY = stroke { p in
            p.move(to: CGPoint(x: 818, y: 77)); p.addLine(to: CGPoint(x: 735, y: 277))
        }
        return [k, e, e.copy(using: &shift)!, p, leftY, rightY]
    }
    static func wordmarkPaths(in rect: CGRect) -> [CGPath] { fit(wordmarkPaths, in: rect) }
    private static var key: CGPath {
        let path = CGMutablePath()
        let join = sqrt(CGFloat(11 * 11 - 4 * 4))
        path.move(to: CGPoint(x: 4, y: join))
        for point in [CGPoint(x: 4, y: 34), CGPoint(x: 11, y: 34),
                      CGPoint(x: 11, y: 40), CGPoint(x: 4, y: 40),
                      CGPoint(x: 4, y: 50), CGPoint(x: 10, y: 50),
                      CGPoint(x: 10, y: 57), CGPoint(x: -4, y: 57),
                      CGPoint(x: -4, y: join)] {
            path.addLine(to: point)
        }
        let angle = acos(CGFloat(4) / 11)
        path.addArc(center: .zero, radius: 11, startAngle: .pi - angle, endAngle: 2 * .pi + angle, clockwise: false)
        path.closeSubpath()
        path.addEllipse(in: CGRect(x: -4, y: -4, width: 8, height: 8))
        return path
    }
    static var paths: [CGPath] {
        var result: [CGPath] = []
        for (x, y, degrees) in [(CGFloat(27), CGFloat(35), CGFloat(24)), (73, 35, -24), (50, 42, 0)] {
            let angle = degrees * .pi / 180
            var transform = CGAffineTransform(a: cos(angle), b: sin(angle), c: -sin(angle), d: cos(angle), tx: x, ty: y)
            result.append(key.copy(using: &transform)!)
        }
        let ring = CGMutablePath()
        ring.addEllipse(in: CGRect(x: 25, y: -7, width: 50, height: 50))
        ring.addEllipse(in: CGRect(x: 32, y: 0, width: 36, height: 36))
        result.insert(ring, at: 0)
        return result
    }
    static func paths(in rect: CGRect) -> [CGPath] {
        fit(paths, in: rect)
    }
    private static func fit(_ source: [CGPath], in rect: CGRect) -> [CGPath] {
        let bounds = source.reduce(CGRect.null) { $0.union($1.boundingBoxOfPath) }
        let scale = min(rect.width / bounds.width, rect.height / bounds.height)
        var transform = CGAffineTransform(a: scale, b: 0, c: 0, d: scale,
                                         tx: rect.midX - bounds.midX * scale,
                                         ty: rect.midY - bounds.midY * scale)
        return source.map { $0.copy(using: &transform)! }
    }
    static let menuBarImage: NSImage = {
        let image = NSImage(size: NSSize(width: 20, height: 20), flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.setFillColor(NSColor.black.cgColor)
            for path in paths(in: CGRect(x: 1, y: 1, width: 18, height: 18)) {
                context.addPath(path); context.drawPath(using: .eoFill)
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = name
        return image
    }()
}

struct AppLogoView: View {
    var colored = false
    var body: some View {
        Canvas { context, size in
            for (index, path) in AppLogo.paths(in: CGRect(origin: .zero, size: size)).enumerated() {
                context.fill(Path(path), with: colored ? .color(Color(cgColor: AppLogo.color(for: index))) : .foreground, style: FillStyle(eoFill: true))
            }
        }.accessibilityLabel(AppLogo.name)
    }
}

struct AppWordmarkView: View {
    var body: some View {
        Canvas { context, size in
            for (index, path) in AppLogo.wordmarkPaths(in: CGRect(origin: .zero, size: size)).enumerated() {
                context.fill(Path(path), with: .color(Color(cgColor: index == 5 ? AppLogo.blue : AppLogo.green)))
            }
        }.accessibilityLabel(AppLogo.name)
    }
}
