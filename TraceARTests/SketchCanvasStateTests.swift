import XCTest
@testable import TraceAR

@MainActor
final class SketchCanvasStateTests: XCTestCase {

    func testAddStrokeEnablesUndoAndClearsRedo() {
        let vm = SketchCanvasViewModel()
        XCTAssertTrue(vm.isEmpty)
        XCTAssertFalse(vm.canUndo)
        XCTAssertFalse(vm.canRedo)

        vm.beginStroke(at: CGPoint(x: 10, y: 10))
        vm.appendPoint(CGPoint(x: 40, y: 50))
        vm.endStroke()

        XCTAssertEqual(vm.strokes.count, 1)
        XCTAssertTrue(vm.canUndo)
        XCTAssertFalse(vm.canRedo)
    }

    func testUndoAndRedoRoundTrip() {
        let vm = SketchCanvasViewModel()
        let first = SketchStroke(
            points: [CGPoint(x: 0, y: 0), CGPoint(x: 20, y: 20)],
            tool: .pencil,
            size: .small,
            color: .inkBlack
        )
        let second = SketchStroke(
            points: [CGPoint(x: 30, y: 30), CGPoint(x: 60, y: 80)],
            tool: .pencil,
            size: .large,
            color: .crimsonRed
        )

        vm.addCompleteStroke(first)
        vm.addCompleteStroke(second)
        XCTAssertEqual(vm.strokes.count, 2)

        vm.undo()
        XCTAssertEqual(vm.strokes, [first])
        XCTAssertTrue(vm.canUndo)
        XCTAssertTrue(vm.canRedo)

        vm.undo()
        XCTAssertTrue(vm.strokes.isEmpty)
        XCTAssertFalse(vm.canUndo)
        XCTAssertTrue(vm.canRedo)

        vm.redo()
        XCTAssertEqual(vm.strokes, [first])

        vm.redo()
        XCTAssertEqual(vm.strokes, [first, second])
        XCTAssertFalse(vm.canRedo)
    }

    func testNewStrokeAfterUndoClearsRedoStack() {
        let vm = SketchCanvasViewModel()
        vm.addCompleteStroke(
            SketchStroke(points: [CGPoint(x: 5, y: 5), CGPoint(x: 15, y: 15)], tool: .pencil, size: .medium, color: .royalBlue)
        )
        vm.addCompleteStroke(
            SketchStroke(points: [CGPoint(x: 25, y: 25), CGPoint(x: 35, y: 35)], tool: .pencil, size: .medium, color: .forestGreen)
        )

        vm.undo()
        XCTAssertTrue(vm.canRedo)

        vm.addCompleteStroke(
            SketchStroke(points: [CGPoint(x: 50, y: 50), CGPoint(x: 70, y: 70)], tool: .eraser, size: .large, color: .inkBlack)
        )
        XCTAssertFalse(vm.canRedo)
        XCTAssertEqual(vm.strokes.count, 2)
    }

    func testClearCanvasIsUndoable() {
        let vm = SketchCanvasViewModel()
        let stroke = SketchStroke(
            points: [CGPoint(x: 12, y: 18), CGPoint(x: 90, y: 110)],
            tool: .pencil,
            size: .medium,
            color: .deepPurple
        )
        vm.addCompleteStroke(stroke)

        vm.clearCanvas()
        XCTAssertTrue(vm.strokes.isEmpty)
        XCTAssertTrue(vm.canUndo)

        vm.undo()
        XCTAssertEqual(vm.strokes, [stroke])
    }

    func testBrushSizesAndSixColorsConfiguration() {
        XCTAssertEqual(BrushSizePreset.allCases.count, 3)
        XCTAssertLessThan(BrushSizePreset.small.pointWidth, BrushSizePreset.medium.pointWidth)
        XCTAssertLessThan(BrushSizePreset.medium.pointWidth, BrushSizePreset.large.pointWidth)

        XCTAssertEqual(SketchColorChoice.allCases.count, 6)
        let names = Set(SketchColorChoice.allCases.map(\.displayName))
        XCTAssertEqual(names.count, 6)
    }

    func testMemoryWarningTrimsUndoHistoryAndClearsRedo() {
        let vm = SketchCanvasViewModel()
        for i in 0..<20 {
            let pt = CGFloat(i * 5)
            vm.addCompleteStroke(
                SketchStroke(points: [CGPoint(x: pt, y: pt), CGPoint(x: pt + 10, y: pt + 10)], tool: .pencil, size: .small, color: .inkBlack)
            )
        }
        vm.undo()
        XCTAssertTrue(vm.canRedo)
        XCTAssertEqual(vm.undoDepth, 19)

        vm.handleMemoryWarning(keepLastUndoLevels: 5)
        XCTAssertFalse(vm.canRedo)
        XCTAssertEqual(vm.undoDepth, 5)
        XCTAssertEqual(vm.strokes.count, 19)
    }

    func testPointDeduplicationSkipsSubpixelJitter() {
        let vm = SketchCanvasViewModel()
        vm.beginStroke(at: CGPoint(x: 100, y: 100))
        vm.appendPoint(CGPoint(x: 100.2, y: 100.2)) // Too close (< sqrt(1.5)), ignored
        vm.appendPoint(CGPoint(x: 108, y: 108))     // Accepted
        vm.endStroke()

        XCTAssertEqual(vm.strokes.first?.points.count, 2)
    }
}
