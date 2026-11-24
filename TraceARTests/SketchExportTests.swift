import XCTest
import UIKit
@testable import TraceAR

final class SketchExportTests: XCTestCase {

    func testRenderPNGDataProducesValidNonEmptyPNG() {
        let stroke = SketchStroke(
            points: [CGPoint(x: 20, y: 20), CGPoint(x: 100, y: 100), CGPoint(x: 180, y: 60)],
            tool: .pencil,
            size: .medium,
            color: .royalBlue
        )

        let pngData = SketchRenderer.renderPNGData(
            strokes: [stroke],
            canvasSize: CGSize(width: 200, height: 200),
            scale: 2.0
        )

        XCTAssertNotNil(pngData)
        XCTAssertGreaterThan(pngData?.count ?? 0, 200)

        let decoded = pngData.flatMap { UIImage(data: $0) }
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.cgImage?.width, 400)
        XCTAssertEqual(decoded?.cgImage?.height, 400)
    }

    func testEraserRestoresWhitePaperWithoutCorruptingBackground() {
        let canvasSize = CGSize(width: 120, height: 120)
        let centerLine = SketchStroke(
            points: [CGPoint(x: 10, y: 60), CGPoint(x: 110, y: 60)],
            tool: .pencil,
            size: .large,
            color: .inkBlack
        )

        guard let inkedImage = SketchRenderer.renderImage(
            strokes: [centerLine],
            canvasSize: canvasSize,
            scale: 1.0,
            paperColor: .white
        ), let inkedPixel = sampleRGB(in: inkedImage, x: 60, y: 60) else {
            XCTFail("Failed to sample inked image")
            return
        }

        // Center pixel should be dark ink before erasing.
        XCTAssertLessThan(inkedPixel.r, 80)

        let eraserPass = SketchStroke(
            points: [CGPoint(x: 60, y: 10), CGPoint(x: 60, y: 110)],
            tool: .eraser,
            size: .large,
            color: .inkBlack
        )

        guard let erasedImage = SketchRenderer.renderImage(
            strokes: [centerLine, eraserPass],
            canvasSize: canvasSize,
            scale: 1.0,
            paperColor: .white
        ), let erasedPixel = sampleRGB(in: erasedImage, x: 60, y: 60) else {
            XCTFail("Failed to sample erased image")
            return
        }

        // Center pixel should return to white paper after eraser pass.
        XCTAssertGreaterThan(erasedPixel.r, 245)
        XCTAssertGreaterThan(erasedPixel.g, 245)
        XCTAssertGreaterThan(erasedPixel.b, 245)
    }

    func testTemporaryPNGExportWritesReadableFile() {
        let sample = SampleShapeGenerator.generate(.perspectiveCube, dimension: 256)
        guard let url = PhotoLibraryService.writeTemporaryPNG(sample, filenamePrefix: "UnitTestSketch") else {
            XCTFail("Expected temporary PNG URL")
            return
        }
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let data = try? Data(contentsOf: url)
        XCTAssertNotNil(data)
        XCTAssertNotNil(data.flatMap { UIImage(data: $0) })
    }

    func testAllSixSampleShapesGenerateValidImages() {
        for kind in SampleShapeKind.allCases {
            let image = SampleShapeGenerator.generate(kind, dimension: 512)
            XCTAssertEqual(image.size.width, 512, "Width mismatch for \(kind)")
            XCTAssertEqual(image.size.height, 512, "Height mismatch for \(kind)")
            XCTAssertNotNil(image.cgImage, "Missing CGImage for \(kind)")
        }
    }

    private func sampleRGB(in image: UIImage, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8)? {
        guard let cg = image.cgImage,
              x >= 0, x < cg.width,
              y >= 0, y < cg.height else { return nil }

        var pixel = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.translateBy(x: CGFloat(-x), y: CGFloat(y - cg.height + 1))
        context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        return (pixel[0], pixel[1], pixel[2])
    }
}
