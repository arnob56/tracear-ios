import SwiftUI
import UIKit

enum SketchTool: String, CaseIterable, Identifiable, Equatable {
    case pencil = "Pencil"
    case eraser = "Eraser"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .pencil:
            return "pencil.tip"
        case .eraser:
            return "eraser.fill"
        }
    }
}

enum BrushSizePreset: String, CaseIterable, Identifiable, Equatable {
    case small
    case medium
    case large

    var id: String { rawValue }

    var pointWidth: CGFloat {
        switch self {
        case .small:
            return 3.0
        case .medium:
            return 8.0
        case .large:
            return 16.0
        }
    }

    var shortLabel: String {
        switch self {
        case .small:
            return "S"
        case .medium:
            return "M"
        case .large:
            return "L"
        }
    }

    var accessibilityName: String {
        switch self {
        case .small:
            return "Small brush, 3 points"
        case .medium:
            return "Medium brush, 8 points"
        case .large:
            return "Large brush, 16 points"
        }
    }
}

enum SketchColorChoice: String, CaseIterable, Identifiable, Equatable {
    case inkBlack
    case crimsonRed
    case royalBlue
    case forestGreen
    case warmAmber
    case deepPurple

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .inkBlack:
            return "Ink Black"
        case .crimsonRed:
            return "Crimson Red"
        case .royalBlue:
            return "Royal Blue"
        case .forestGreen:
            return "Forest Green"
        case .warmAmber:
            return "Warm Amber"
        case .deepPurple:
            return "Deep Purple"
        }
    }

    var rgb: (r: CGFloat, g: CGFloat, b: CGFloat) {
        switch self {
        case .inkBlack:
            return (0.08, 0.09, 0.11)
        case .crimsonRed:
            return (0.85, 0.17, 0.17)
        case .royalBlue:
            return (0.11, 0.37, 0.84)
        case .forestGreen:
            return (0.12, 0.54, 0.27)
        case .warmAmber:
            return (0.88, 0.48, 0.00)
        case .deepPurple:
            return (0.48, 0.17, 0.75)
        }
    }

    var uiColor: UIColor {
        let components = rgb
        return UIColor(red: components.r, green: components.g, blue: components.b, alpha: 1.0)
    }

    var swiftUIColor: Color {
        let components = rgb
        return Color(red: components.r, green: components.g, blue: components.b)
    }
}

struct SketchStroke: Identifiable, Equatable {
    let id: UUID
    var points: [CGPoint]
    var tool: SketchTool
    var size: BrushSizePreset
    var color: SketchColorChoice

    init(
        id: UUID = UUID(),
        points: [CGPoint],
        tool: SketchTool,
        size: BrushSizePreset,
        color: SketchColorChoice
    ) {
        self.id = id
        self.points = points
        self.tool = tool
        self.size = size
        self.color = color
    }

    var effectiveLineWidth: CGFloat {
        tool == .eraser ? size.pointWidth * 1.6 : size.pointWidth
    }
}

@MainActor
final class SketchCanvasViewModel: ObservableObject {
    static let maxUndoLevels = 50

    @Published var selectedTool: SketchTool = .pencil
    @Published var selectedSize: BrushSizePreset = .medium
    @Published var selectedColor: SketchColorChoice = .inkBlack
    @Published var showReferenceUnderlay: Bool = false
    @Published var underlayOpacity: Double = 0.25

    @Published private(set) var strokes: [SketchStroke] = []
    @Published private(set) var activeStroke: SketchStroke?

    private var undoStack: [[SketchStroke]] = []
    private var redoStack: [[SketchStroke]] = []

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var isEmpty: Bool { strokes.isEmpty && activeStroke == nil }

    var undoDepth: Int { undoStack.count }
    var redoDepth: Int { redoStack.count }

    func beginStroke(at point: CGPoint) {
        if activeStroke != nil {
            endStroke()
        }
        activeStroke = SketchStroke(
            points: [point],
            tool: selectedTool,
            size: selectedSize,
            color: selectedColor
        )
    }

    func appendPoint(_ point: CGPoint) {
        guard var stroke = activeStroke else {
            beginStroke(at: point)
            return
        }
        if let last = stroke.points.last {
            let dx = point.x - last.x
            let dy = point.y - last.y
            guard (dx * dx + dy * dy) >= 1.5 else { return }
        }
        stroke.points.append(point)
        activeStroke = stroke
    }

    func endStroke() {
        guard let finished = activeStroke else { return }
        activeStroke = nil
        guard !finished.points.isEmpty else { return }
        pushUndoSnapshot()
        strokes.append(finished)
        redoStack.removeAll()
    }

    func addCompleteStroke(_ stroke: SketchStroke) {
        guard !stroke.points.isEmpty else { return }
        pushUndoSnapshot()
        strokes.append(stroke)
        redoStack.removeAll()
    }

    func undo() {
        activeStroke = nil
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(strokes)
        strokes = previous
    }

    func redo() {
        activeStroke = nil
        guard let next = redoStack.popLast() else { return }
        undoStack.append(strokes)
        strokes = next
    }

    func clearCanvas() {
        activeStroke = nil
        guard !strokes.isEmpty else { return }
        pushUndoSnapshot()
        strokes.removeAll()
        redoStack.removeAll()
    }

    func handleMemoryWarning(keepLastUndoLevels: Int = 8) {
        redoStack.removeAll()
        if undoStack.count > keepLastUndoLevels {
            undoStack.removeFirst(undoStack.count - max(0, keepLastUndoLevels))
        }
    }

    private func pushUndoSnapshot() {
        undoStack.append(strokes)
        if undoStack.count > Self.maxUndoLevels {
            undoStack.removeFirst(undoStack.count - Self.maxUndoLevels)
        }
    }
}
