import UIKit

enum SampleShapeGenerator {
    static func generate(_ kind: SampleShapeKind, dimension: CGFloat = 1024) -> UIImage {
        let size = CGSize(width: dimension, height: dimension)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = false

        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            let rect = CGRect(origin: .zero, size: size)

            // Soft translucent paper card background so both normal and outline filters work cleanly.
            UIColor(white: 0.99, alpha: 0.92).setFill()
            UIBezierPath(roundedRect: rect.insetBy(dx: 24, dy: 24), cornerRadius: 32).fill()

            cg.setLineCap(.round)
            cg.setLineJoin(.round)

            let primaryInk = UIColor(red: 0.10, green: 0.12, blue: 0.16, alpha: 1.0)
            let guideInk = UIColor(red: 0.25, green: 0.45, blue: 0.78, alpha: 0.55)

            switch kind {
            case .perspectiveCube:
                drawPerspectiveCube(in: rect, primary: primaryInk, guide: guideInk)
            case .loomisHead:
                drawLoomisHead(in: rect, primary: primaryInk, guide: guideInk)
            case .botanicalLeaf:
                drawBotanicalLeaf(in: rect, primary: primaryInk, guide: guideInk)
            case .teacup:
                drawTeacup(in: rect, primary: primaryInk, guide: guideInk)
            case .starMandala:
                drawStarMandala(in: rect, primary: primaryInk, guide: guideInk)
            case .sittingCat:
                drawSittingCat(in: rect, primary: primaryInk, guide: guideInk)
            }
        }
    }

    private static func drawPerspectiveCube(in rect: CGRect, primary: UIColor, guide: UIColor) {
        let w = rect.width
        let h = rect.height

        let top = CGPoint(x: w * 0.50, y: h * 0.16)
        let leftTop = CGPoint(x: w * 0.19, y: h * 0.34)
        let rightTop = CGPoint(x: w * 0.81, y: h * 0.34)
        let centerMid = CGPoint(x: w * 0.50, y: h * 0.52)
        let leftBot = CGPoint(x: w * 0.19, y: h * 0.70)
        let rightBot = CGPoint(x: w * 0.81, y: h * 0.70)
        let bottom = CGPoint(x: w * 0.50, y: h * 0.86)
        let hiddenCenter = CGPoint(x: w * 0.50, y: h * 0.50)

        // Hidden back edges (dashed construction guide)
        let dashed = UIBezierPath()
        dashed.move(to: top)
        dashed.addLine(to: hiddenCenter)
        dashed.move(to: leftBot)
        dashed.addLine(to: hiddenCenter)
        dashed.move(to: rightBot)
        dashed.addLine(to: hiddenCenter)
        guide.setStroke()
        dashed.lineWidth = w * 0.006
        let pattern: [CGFloat] = [14, 12]
        dashed.setLineDash(pattern, count: pattern.count, phase: 0)
        dashed.stroke()

        // Visible outer hexagon + interior Y edges
        let solid = UIBezierPath()
        solid.move(to: top)
        solid.addLine(to: rightTop)
        solid.addLine(to: rightBot)
        solid.addLine(to: bottom)
        solid.addLine(to: leftBot)
        solid.addLine(to: leftTop)
        solid.close()

        solid.move(to: leftTop)
        solid.addLine(to: centerMid)
        solid.addLine(to: rightTop)
        solid.move(to: centerMid)
        solid.addLine(to: bottom)

        primary.setStroke()
        solid.lineWidth = w * 0.011
        solid.stroke()
    }

    private static func drawLoomisHead(in rect: CGRect, primary: UIColor, guide: UIColor) {
        let w = rect.width
        let h = rect.height
        let cx = w * 0.50
        let sphereCenter = CGPoint(x: cx, y: h * 0.40)
        let radius = w * 0.25

        // Cranial sphere + side plane ellipse
        let cranium = UIBezierPath(
            arcCenter: sphereCenter,
            radius: radius,
            startAngle: 0,
            endAngle: .pi * 2,
            clockwise: true
        )
        let sidePlane = UIBezierPath(
            ovalIn: CGRect(
                x: cx + radius * 0.42,
                y: sphereCenter.y - radius * 0.66,
                width: radius * 0.42,
                height: radius * 1.32
            )
        )

        // Proportion lines: hairline, brow, nose base, chin
        let guides = UIBezierPath()
        let browY = sphereCenter.y
        let hairY = sphereCenter.y - radius * 0.58
        let noseY = sphereCenter.y + radius * 0.58
        let chinY = sphereCenter.y + radius * 1.18

        for y in [hairY, browY, noseY, chinY] {
            guides.move(to: CGPoint(x: cx - radius * 1.15, y: y))
            guides.addLine(to: CGPoint(x: cx + radius * 1.15, y: y))
        }
        // Center vertical axis
        guides.move(to: CGPoint(x: cx - radius * 0.12, y: sphereCenter.y - radius * 1.05))
        guides.addQuadCurve(
            to: CGPoint(x: cx - radius * 0.08, y: chinY),
            controlPoint: CGPoint(x: cx - radius * 0.24, y: noseY)
        )

        guide.setStroke()
        sidePlane.lineWidth = w * 0.006
        sidePlane.stroke()
        guides.lineWidth = w * 0.006
        guides.stroke()

        // Jaw contour
        let jaw = UIBezierPath()
        jaw.move(to: CGPoint(x: cx - radius * 0.94, y: browY + radius * 0.12))
        jaw.addQuadCurve(
            to: CGPoint(x: cx - radius * 0.10, y: chinY),
            controlPoint: CGPoint(x: cx - radius * 0.82, y: chinY - radius * 0.12)
        )
        jaw.addQuadCurve(
            to: CGPoint(x: cx + radius * 0.85, y: browY + radius * 0.24),
            controlPoint: CGPoint(x: cx + radius * 0.65, y: chinY - radius * 0.08)
        )

        primary.setStroke()
        cranium.lineWidth = w * 0.010
        cranium.stroke()
        jaw.lineWidth = w * 0.011
        jaw.stroke()
    }

    private static func drawBotanicalLeaf(in rect: CGRect, primary: UIColor, guide: UIColor) {
        let w = rect.width
        let h = rect.height

        let tip = CGPoint(x: w * 0.68, y: h * 0.15)
        let base = CGPoint(x: w * 0.30, y: h * 0.80)
        let stemEnd = CGPoint(x: w * 0.22, y: h * 0.88)

        let leaf = UIBezierPath()
        leaf.move(to: base)
        leaf.addCurve(
            to: tip,
            controlPoint1: CGPoint(x: w * 0.12, y: h * 0.50),
            controlPoint2: CGPoint(x: w * 0.36, y: h * 0.20)
        )
        leaf.addCurve(
            to: base,
            controlPoint1: CGPoint(x: w * 0.82, y: h * 0.42),
            controlPoint2: CGPoint(x: w * 0.62, y: h * 0.78)
        )

        let midrib = UIBezierPath()
        midrib.move(to: stemEnd)
        midrib.addQuadCurve(
            to: tip,
            controlPoint: CGPoint(x: w * 0.46, y: h * 0.50)
        )

        let veins = UIBezierPath()
        let veinSteps: [CGFloat] = [0.28, 0.44, 0.60, 0.75]
        for t in veinSteps {
            let vx = base.x + (tip.x - base.x) * t
            let vy = base.y + (tip.y - base.y) * t
            let span = (1.0 - abs(t - 0.5) * 1.4) * w * 0.16
            veins.move(to: CGPoint(x: vx, y: vy))
            veins.addQuadCurve(
                to: CGPoint(x: vx - span * 0.9, y: vy - span * 0.55),
                controlPoint: CGPoint(x: vx - span * 0.45, y: vy - span * 0.15)
            )
            veins.move(to: CGPoint(x: vx, y: vy))
            veins.addQuadCurve(
                to: CGPoint(x: vx + span * 0.85, y: vy + span * 0.15),
                controlPoint: CGPoint(x: vx + span * 0.45, y: vy + span * 0.22)
            )
        }

        guide.setStroke()
        veins.lineWidth = w * 0.006
        veins.stroke()

        primary.setStroke()
        leaf.lineWidth = w * 0.011
        leaf.stroke()
        midrib.lineWidth = w * 0.009
        midrib.stroke()
    }

    private static func drawTeacup(in rect: CGRect, primary: UIColor, guide: UIColor) {
        let w = rect.width
        let h = rect.height
        let cx = w * 0.46

        // Symmetry centerline
        let axis = UIBezierPath()
        axis.move(to: CGPoint(x: cx, y: h * 0.20))
        axis.addLine(to: CGPoint(x: cx, y: h * 0.84))
        guide.setStroke()
        axis.lineWidth = w * 0.005
        axis.stroke()

        // Saucer ellipse
        let saucer = UIBezierPath(
            ovalIn: CGRect(x: cx - w * 0.34, y: h * 0.66, width: w * 0.68, height: h * 0.14)
        )
        // Rim ellipse
        let rim = UIBezierPath(
            ovalIn: CGRect(x: cx - w * 0.24, y: h * 0.28, width: w * 0.48, height: h * 0.11)
        )

        // Cup bowl
        let bowl = UIBezierPath()
        bowl.move(to: CGPoint(x: cx - w * 0.24, y: h * 0.335))
        bowl.addCurve(
            to: CGPoint(x: cx - w * 0.10, y: h * 0.70),
            controlPoint1: CGPoint(x: cx - w * 0.24, y: h * 0.56),
            controlPoint2: CGPoint(x: cx - w * 0.15, y: h * 0.68)
        )
        bowl.addQuadCurve(
            to: CGPoint(x: cx + w * 0.10, y: h * 0.70),
            controlPoint: CGPoint(x: cx, y: h * 0.73)
        )
        bowl.addCurve(
            to: CGPoint(x: cx + w * 0.24, y: h * 0.335),
            controlPoint1: CGPoint(x: cx + w * 0.15, y: h * 0.68),
            controlPoint2: CGPoint(x: cx + w * 0.24, y: h * 0.56)
        )

        // Handle
        let handle = UIBezierPath()
        handle.move(to: CGPoint(x: cx + w * 0.23, y: h * 0.39))
        handle.addCurve(
            to: CGPoint(x: cx + w * 0.16, y: h * 0.60),
            controlPoint1: CGPoint(x: cx + w * 0.40, y: h * 0.36),
            controlPoint2: CGPoint(x: cx + w * 0.38, y: h * 0.62)
        )

        primary.setStroke()
        for path in [saucer, rim, bowl, handle] {
            path.lineWidth = w * 0.010
            path.stroke()
        }
    }

    private static func drawStarMandala(in rect: CGRect, primary: UIColor, guide: UIColor) {
        let w = rect.width
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerR = w * 0.36
        let midR = w * 0.22
        let innerR = w * 0.11

        let circles = UIBezierPath()
        for r in [outerR, midR, innerR] {
            circles.append(
                UIBezierPath(arcCenter: center, radius: r, startAngle: 0, endAngle: .pi * 2, clockwise: true)
            )
        }
        guide.setStroke()
        circles.lineWidth = w * 0.005
        circles.stroke()

        let star = UIBezierPath()
        let points = 8
        for i in 0..<(points * 2) {
            let angle = (CGFloat(i) * .pi / CGFloat(points)) - (.pi / 2)
            let radius = (i % 2 == 0) ? outerR : innerR * 1.45
            let pt = CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
            if i == 0 {
                star.move(to: pt)
            } else {
                star.addLine(to: pt)
            }
        }
        star.close()

        primary.setStroke()
        star.lineWidth = w * 0.010
        star.stroke()
    }

    private static func drawSittingCat(in rect: CGRect, primary: UIColor, guide: UIColor) {
        let w = rect.width
        let h = rect.height
        let cx = w * 0.48

        // Simple head & torso construction circles
        let headCenter = CGPoint(x: cx, y: h * 0.33)
        let headRadius = w * 0.13
        let construction = UIBezierPath(
            arcCenter: headCenter,
            radius: headRadius,
            startAngle: 0,
            endAngle: .pi * 2,
            clockwise: true
        )
        construction.append(
            UIBezierPath(ovalIn: CGRect(x: cx - w * 0.15, y: h * 0.45, width: w * 0.30, height: h * 0.36))
        )
        guide.setStroke()
        construction.lineWidth = w * 0.005
        construction.stroke()

        // Outer cat contour: ears, cheeks, back, sitting paws, curled tail
        let cat = UIBezierPath()
        // Left ear
        cat.move(to: CGPoint(x: cx - w * 0.11, y: h * 0.25))
        cat.addLine(to: CGPoint(x: cx - w * 0.14, y: h * 0.14))
        cat.addLine(to: CGPoint(x: cx - w * 0.04, y: h * 0.21))
        // Forehead to right ear
        cat.addQuadCurve(
            to: CGPoint(x: cx + w * 0.04, y: h * 0.21),
            controlPoint: CGPoint(x: cx, y: h * 0.20)
        )
        cat.addLine(to: CGPoint(x: cx + w * 0.14, y: h * 0.14))
        cat.addLine(to: CGPoint(x: cx + w * 0.11, y: h * 0.25))
        // Right cheek & arched back
        cat.addQuadCurve(
            to: CGPoint(x: cx + w * 0.09, y: h * 0.43),
            controlPoint: CGPoint(x: cx + w * 0.16, y: h * 0.35)
        )
        cat.addCurve(
            to: CGPoint(x: cx + w * 0.13, y: h * 0.80),
            controlPoint1: CGPoint(x: cx + w * 0.20, y: h * 0.54),
            controlPoint2: CGPoint(x: cx + w * 0.20, y: h * 0.72)
        )
        // Base & front paws
        cat.addLine(to: CGPoint(x: cx - w * 0.12, y: h * 0.80))
        cat.addCurve(
            to: CGPoint(x: cx - w * 0.09, y: h * 0.43),
            controlPoint1: CGPoint(x: cx - w * 0.17, y: h * 0.68),
            controlPoint2: CGPoint(x: cx - w * 0.14, y: h * 0.52)
        )
        cat.addQuadCurve(
            to: CGPoint(x: cx - w * 0.11, y: h * 0.25),
            controlPoint: CGPoint(x: cx - w * 0.16, y: h * 0.35)
        )

        // Curled tail
        let tail = UIBezierPath()
        tail.move(to: CGPoint(x: cx + w * 0.14, y: h * 0.77))
        tail.addCurve(
            to: CGPoint(x: cx + w * 0.27, y: h * 0.58),
            controlPoint1: CGPoint(x: cx + w * 0.30, y: h * 0.80),
            controlPoint2: CGPoint(x: cx + w * 0.34, y: h * 0.66)
        )

        primary.setStroke()
        cat.lineWidth = w * 0.010
        cat.stroke()
        tail.lineWidth = w * 0.010
        tail.stroke()
    }
}
