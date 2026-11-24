import Foundation

enum AppErrorAction: Equatable {
    case openSettings
    case switchToSketchPad
    case retryPlaneScan
    case placeAtFallbackDepth
    case reanchorImage
    case openSampleShapes
    case shareInstead
    case resetFilters
    case dismiss

    var buttonTitle: String {
        switch self {
        case .openSettings:
            return "Open Settings"
        case .switchToSketchPad:
            return "Use Sketch Pad"
        case .retryPlaneScan:
            return "Retry Scan"
        case .placeAtFallbackDepth:
            return "Place 25 cm Ahead"
        case .reanchorImage:
            return "Re-anchor Image"
        case .openSampleShapes:
            return "Use Sample Shape"
        case .shareInstead:
            return "Share Instead"
        case .resetFilters:
            return "Reset Filters"
        case .dismiss:
            return "Dismiss"
        }
    }
}

struct AppErrorState: Identifiable, Equatable {
    enum Kind: Equatable {
        case cameraPermissionDenied
        case photoSavePermissionDenied
        case arkitUnsupported
        case noPlaneFound
        case lowLight
        case trackingLimited(reason: String)
        case imageImportFailed(detail: String)
        case saveFailed(detail: String)
        case memoryWarning
    }

    let id: UUID
    let kind: Kind
    let title: String
    let message: String
    let iconName: String
    let primaryAction: AppErrorAction
    let secondaryAction: AppErrorAction?

    init(
        id: UUID = UUID(),
        kind: Kind,
        title: String,
        message: String,
        iconName: String,
        primaryAction: AppErrorAction,
        secondaryAction: AppErrorAction? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.message = message
        self.iconName = iconName
        self.primaryAction = primaryAction
        self.secondaryAction = secondaryAction
    }

    static func == (lhs: AppErrorState, rhs: AppErrorState) -> Bool {
        lhs.kind == rhs.kind &&
        lhs.title == rhs.title &&
        lhs.message == rhs.message &&
        lhs.primaryAction == rhs.primaryAction &&
        lhs.secondaryAction == rhs.secondaryAction
    }

    static func cameraPermissionDenied() -> AppErrorState {
        AppErrorState(
            kind: .cameraPermissionDenied,
            title: "Camera Access Needed",
            message: "TraceAR needs camera access to show your paper and anchor your tracing reference. Video never leaves your iPhone.",
            iconName: "video.slash.fill",
            primaryAction: .openSettings,
            secondaryAction: .switchToSketchPad
        )
    }

    static func photoSavePermissionDenied() -> AppErrorState {
        AppErrorState(
            kind: .photoSavePermissionDenied,
            title: "Photos Permission Denied",
            message: "Allow Photos (\"Add Photos Only\") in Settings to save sketches directly, or share your image instead.",
            iconName: "photo.on.rectangle",
            primaryAction: .openSettings,
            secondaryAction: .shareInstead
        )
    }

    static func arkitUnsupported() -> AppErrorState {
        AppErrorState(
            kind: .arkitUnsupported,
            title: "AR Tracking Not Supported",
            message: "This device or environment does not support AR world tracking. You can still draw and export using Sketch Pad.",
            iconName: "arkit",
            primaryAction: .switchToSketchPad,
            secondaryAction: .dismiss
        )
    }

    static func noPlaneFound() -> AppErrorState {
        AppErrorState(
            kind: .noPlaneFound,
            title: "No Flat Surface Detected Yet",
            message: "Move slowly over well-lit paper with visible edges or a table surface, or place your guide at a fixed 25 cm stand height.",
            iconName: "viewfinder",
            primaryAction: .placeAtFallbackDepth,
            secondaryAction: .retryPlaneScan
        )
    }

    static func lowLight() -> AppErrorState {
        AppErrorState(
            kind: .lowLight,
            title: "Low Light Detected",
            message: "Turn on a desk lamp or move near a window so your anchored drawing stays rock-steady on the paper.",
            iconName: "sun.min.fill",
            primaryAction: .dismiss
        )
    }

    static func trackingLimited(reason: String) -> AppErrorState {
        AppErrorState(
            kind: .trackingLimited(reason: reason),
            title: "Surface Tracking Needs Attention",
            message: reason,
            iconName: "exclamationmark.triangle.fill",
            primaryAction: .reanchorImage,
            secondaryAction: .dismiss
        )
    }

    static func imageImportFailed(detail: String) -> AppErrorState {
        AppErrorState(
            kind: .imageImportFailed(detail: detail),
            title: "Couldn't Load Reference Image",
            message: detail,
            iconName: "photo.fill.on.rectangle.fill",
            primaryAction: .openSampleShapes,
            secondaryAction: .dismiss
        )
    }

    static func saveFailed(detail: String) -> AppErrorState {
        AppErrorState(
            kind: .saveFailed(detail: detail),
            title: "Couldn't Save Image",
            message: detail,
            iconName: "exclamationmark.triangle.fill",
            primaryAction: .shareInstead,
            secondaryAction: .dismiss
        )
    }

    static func memoryWarning() -> AppErrorState {
        AppErrorState(
            kind: .memoryWarning,
            title: "Freed Temporary Memory",
            message: "iOS reported low memory. TraceAR cleared cached image buffers to keep your tracing smooth.",
            iconName: "memorychip",
            primaryAction: .dismiss,
            secondaryAction: .resetFilters
        )
    }
}
