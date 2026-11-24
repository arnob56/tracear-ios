import Foundation
import CoreGraphics

enum AppMode: String, CaseIterable, Identifiable {
    case arTrace = "AR Trace"
    case sketchPad = "Sketch Pad"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .arTrace:
            return "camera.viewfinder"
        case .sketchPad:
            return "pencil.and.outline"
        }
    }
}

struct TraceFilterSettings: Equatable {
    static let minOpacity: Double = 0.05
    static let maxOpacity: Double = 1.0

    var opacity: Double = 0.55 {
        didSet {
            opacity = min(max(opacity, Self.minOpacity), Self.maxOpacity)
        }
    }
    var isOutlineOnly: Bool = false
    var isGrayscale: Bool = false
    var isInverted: Bool = false
    var edgeIntensity: Double = 4.5

    init(
        opacity: Double = 0.55,
        isOutlineOnly: Bool = false,
        isGrayscale: Bool = false,
        isInverted: Bool = false,
        edgeIntensity: Double = 4.5
    ) {
        self.opacity = min(max(opacity, Self.minOpacity), Self.maxOpacity)
        self.isOutlineOnly = isOutlineOnly
        self.isGrayscale = isGrayscale
        self.isInverted = isInverted
        self.edgeIntensity = edgeIntensity
    }

    /// True when Core Image filtering is needed; opacity alone is applied on the GPU node.
    var requiresImageProcessing: Bool {
        isOutlineOnly || isGrayscale || isInverted
    }

    struct FilterCacheKey: Equatable, Hashable {
        let sourceID: UUID
        let isOutlineOnly: Bool
        let isGrayscale: Bool
        let isInverted: Bool
        let edgeIntensityBucket: Int

        init(sourceID: UUID, settings: TraceFilterSettings) {
            self.sourceID = sourceID
            self.isOutlineOnly = settings.isOutlineOnly
            self.isGrayscale = settings.isGrayscale
            self.isInverted = settings.isInverted
            self.edgeIntensityBucket = Int((settings.edgeIntensity * 10).rounded())
        }
    }

    mutating func reset() {
        opacity = 0.55
        isOutlineOnly = false
        isGrayscale = false
        isInverted = false
        edgeIntensity = 4.5
    }
}

enum SampleShapeKind: String, CaseIterable, Identifiable {
    case perspectiveCube
    case loomisHead
    case botanicalLeaf
    case teacup
    case starMandala
    case sittingCat

    var id: String { rawValue }

    var title: String {
        switch self {
        case .perspectiveCube:
            return "3D Perspective Cube"
        case .loomisHead:
            return "Portrait Proportions"
        case .botanicalLeaf:
            return "Botanical Leaf"
        case .teacup:
            return "Teacup & Ellipses"
        case .starMandala:
            return "Geometric Star"
        case .sittingCat:
            return "Cat Contour"
        }
    }

    var subtitle: String {
        switch self {
        case .perspectiveCube:
            return "Angles & parallel edges"
        case .loomisHead:
            return "Head sphere & eye line"
        case .botanicalLeaf:
            return "Organic curves & veins"
        case .teacup:
            return "Symmetry & foreshortening"
        case .starMandala:
            return "Radial balance practice"
        case .sittingCat:
            return "Simple gesture lines"
        }
    }

    var systemIcon: String {
        switch self {
        case .perspectiveCube:
            return "cube.transparent"
        case .loomisHead:
            return "person.crop.circle"
        case .botanicalLeaf:
            return "leaf"
        case .teacup:
            return "cup.and.saucer"
        case .starMandala:
            return "sparkles"
        case .sittingCat:
            return "pawprint"
        }
    }
}
