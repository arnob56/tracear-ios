import UIKit

@MainActor
enum HapticsManager {
    static func placeImpact() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred()
    }

    static func lockChanged(isLocked: Bool) {
        let generator = UIImpactFeedbackGenerator(style: isLocked ? .rigid : .soft)
        generator.prepare()
        generator.impactOccurred()
    }

    static func lightTap() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    static func notifySuccess() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    static func notifyWarning() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
    }
}
