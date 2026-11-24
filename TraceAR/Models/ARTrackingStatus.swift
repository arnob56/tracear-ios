import Foundation
import CoreGraphics

enum TrackingQuality: Equatable {
    case initializing
    case normal
    case limitedExcessiveMotion
    case limitedInsufficientFeatures
    case limitedRelocalizing
    case notAvailable

    enum Severity: Equatable {
        case good
        case caution
        case critical
    }

    var severity: Severity {
        switch self {
        case .normal:
            return .good
        case .initializing, .limitedExcessiveMotion, .limitedInsufficientFeatures, .limitedRelocalizing:
            return .caution
        case .notAvailable:
            return .critical
        }
    }

    var badgeTitle: String {
        switch self {
        case .initializing:
            return "Scanning"
        case .normal:
            return "Steady"
        case .limitedExcessiveMotion:
            return "Too Fast"
        case .limitedInsufficientFeatures:
            return "Low Detail"
        case .limitedRelocalizing:
            return "Relocating"
        case .notAvailable:
            return "Tracking Lost"
        }
    }

    var guidanceMessage: String? {
        switch self {
        case .initializing:
            return "Point your iPhone at well-lit paper or a table and move gently."
        case .normal:
            return nil
        case .limitedExcessiveMotion:
            return "Phone is moving too quickly. Rest it steadily on your stand."
        case .limitedInsufficientFeatures:
            return "Surface lacks visible detail. Keep textured edges or a pencil nearby in view."
        case .limitedRelocalizing:
            return "Recovering surface position. Hold the phone steady over your paper."
        case .notAvailable:
            return "Camera tracking is unavailable. Re-anchor your image once the view stabilizes."
        }
    }

    var countsAsLostForAnchor: Bool {
        switch self {
        case .notAvailable, .limitedRelocalizing, .limitedInsufficientFeatures:
            return true
        case .initializing, .normal, .limitedExcessiveMotion:
            return false
        }
    }
}

struct StabilityMonitor: Equatable {
    static let lowLightEnterThresholdLumens: CGFloat = 350.0
    static let lowLightExitThresholdLumens: CGFloat = 420.0
    static let planeSearchTimeoutSeconds: TimeInterval = 8.0
    static let trackingLostPromptDelaySeconds: TimeInterval = 3.0

    private(set) var quality: TrackingQuality = .initializing
    private(set) var isLowLight: Bool = false
    private(set) var hasDetectedPlane: Bool = false
    private(set) var isNoPlaneTimedOut: Bool = false
    private(set) var shouldPromptReanchor: Bool = false

    private var scanStartedAt: TimeInterval?
    private var trackingDegradedSince: TimeInterval?
    private var reanchorPromptDismissedForIncident: Bool = false

    mutating func beginPlaneScan(now: TimeInterval) {
        hasDetectedPlane = false
        isNoPlaneTimedOut = false
        scanStartedAt = now
    }

    mutating func markPlaneDetected() {
        hasDetectedPlane = true
        isNoPlaneTimedOut = false
    }

    mutating func dismissReanchorPrompt() {
        shouldPromptReanchor = false
        reanchorPromptDismissedForIncident = true
    }

    mutating func resetForReanchor(now: TimeInterval) {
        shouldPromptReanchor = false
        reanchorPromptDismissedForIncident = false
        trackingDegradedSince = nil
        beginPlaneScan(now: now)
    }

    mutating func update(
        quality newQuality: TrackingQuality,
        ambientIntensityLumens: CGFloat?,
        isAnchorPlaced: Bool,
        now: TimeInterval
    ) {
        quality = newQuality

        // Hysteresis prevents banner flicker around 350 lumens.
        if let lumens = ambientIntensityLumens {
            if isLowLight {
                if lumens >= Self.lowLightExitThresholdLumens {
                    isLowLight = false
                }
            } else if lumens < Self.lowLightEnterThresholdLumens {
                isLowLight = true
            }
        }

        // Plane search timeout before anchor placement.
        if !isAnchorPlaced && !hasDetectedPlane {
            if let started = scanStartedAt {
                if now - started >= Self.planeSearchTimeoutSeconds {
                    isNoPlaneTimedOut = true
                }
            } else {
                scanStartedAt = now
            }
        } else {
            isNoPlaneTimedOut = false
        }

        // Auto-prompt to re-anchor when tracking stays degraded while an image is placed.
        if isAnchorPlaced && newQuality.countsAsLostForAnchor {
            if let degradedStart = trackingDegradedSince {
                let elapsed = now - degradedStart
                let requiredDelay = (newQuality == .notAvailable) ? 1.0 : Self.trackingLostPromptDelaySeconds
                if elapsed >= requiredDelay && !reanchorPromptDismissedForIncident {
                    shouldPromptReanchor = true
                }
            } else {
                trackingDegradedSince = now
            }
        } else {
            trackingDegradedSince = nil
            shouldPromptReanchor = false
            if newQuality == .normal {
                reanchorPromptDismissedForIncident = false
            }
        }
    }
}
