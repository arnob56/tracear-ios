import UIKit
import SwiftUI

enum SketchRenderer {
    /// Builds a smooth quadratic midpoint-interpolated path for both live SwiftUI Canvas and PNG export.
    static func buildSwiftUIPath(points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }

        if points.count == 1 {
            let dotRect = CGRect(x: first.x - 0.5, y: first.y - 0.5, width: 1.0, height: 1.0)
            path.addEllipse(in: dotRect)
            return path
        }

        path.move(to: first)
        if points.count == 2 {
            path.addLine(to: points[1])
            return path
        }

        for index in 1..<(points.count - 1) {
            let current = points[index]
            let next = points[index + 1]
            let mid = CGPoint(x: (current.x + next.x) * 0.5, y: (current.y + next.y) * 0.5)
            path.addQuadCurve(to: mid, control: current)
        }
        if let last = points.last {
            path.addLine(to: last)
        }
        return path
    }

    static func buildUIBezierPath(points: [CGPoint]) -> UIBezierPath {
        let bezier = UIBezierPath()
        guard let first = points.first else { return bezier }

        bezier.move(to: first)
        if points.count == 1 {
            bezier.addLine(to: CGPoint(x: first.x + 0.1, y: first.y + 0.1))
            return bezier
        }

        if points.count == 2 {
            bezier.addLine(to: points[1])
            return bezier
        }

        for index in 1..<(points.count - 1) {
            let current = points[index]
            let next = points[index + 1]
            let mid = CGPoint(x: (current.x + next.x) * 0.5, y: (current.y + next.y) * 0.5)
            bezier.addQuadCurve(to: mid, controlPoint: current)
        }
        if let last = points.last {
            bezier.addLine(to: last)
        }
        return bezier
    }

    /// Renders strokes on an isolated transparent ink layer so the eraser clears ink without painting white over the paper or underlay.
    static func renderImage(
        strokes: [SketchStroke],
        canvasSize: CGSize,
        scale: CGFloat = 2.0,
        paperColor: UIColor = .white,
        underlayImage: UIImage? = nil,
        underlayOpacity: CGFloat = 0.0
    ) -> UIImage? {
        guard canvasSize.width > 1, canvasSize.height > 1 else { return nil }
        let bounds = CGRect(origin: .zero, size: canvasSize)

        let inkFormat = UIGraphicsImageRendererFormat()
        inkFormat.scale = scale
        inkFormat.opaque = false
        inkFormat.preferredRange = .standard

        let inkImage = UIGraphicsImageRenderer(size: canvasSize, format: inkFormat).image { ctx in
            let cg = ctx.cgContext
            cg.setLineCap(.round)
            cg.setLineJoin(.round)

            for stroke in strokes where !stroke.points.isEmpty {
                let bezier = buildUIBezierPath(points: stroke.points)
                bezier.lineWidth = stroke.effectiveLineWidth
                bezier.lineCapStyle = .round
                bezier.lineJoinStyle = .round

                switch stroke.tool {
                case .pencil:
                    cg.setBlendMode(.normal)
                    stroke.color.uiColor.setStroke()
                case .eraser:
                    cg.setBlendMode(.clear)
                    UIColor.clear.setStroke()
                }
                bezier.stroke()
            }
        }

        let finalFormat = UIGraphicsImageRendererFormat()
        finalFormat.scale = scale
        finalFormat.opaque = true
        finalFormat.preferredRange = .standard

        return UIGraphicsImageRenderer(size: canvasSize, format: finalFormat).image { _ in
            paperColor.setFill()
            UIRectFill(bounds)

            if let underlayImage, underlayOpacity > 0.01 {
                let fitted = aspectFitRect(imageSize: underlayImage.size, in: bounds.insetBy(dx: 16, dy: 16))
                underlayImage.draw(in: fitted, blendMode: .normal, alpha: underlayOpacity)
            }

            inkImage.draw(in: bounds)
        }
    }

    static func renderPNGData(
        strokes: [SketchStroke],
        canvasSize: CGSize,
        scale: CGFloat = 2.0
    ) -> Data? {
        renderImage(strokes: strokes, canvasSize: canvasSize, scale: scale)?.pngData()
    }

    static func aspectFitRect(imageSize: CGSize, in targetRect: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, targetRect.width > 0, targetRect.height > 0 else {
            return targetRect
        }
        let scale = min(targetRect.width / imageSize.width, targetRect.height / imageSize.height)
        let width = imageSize.width * scale
        let height = imageSize.height * scale
        return CGRect(
            x: targetRect.midX - width * 0.5,
            y: targetRect.midY - height * 0.5,
            width: width,
            height: height
        )
    }
}
