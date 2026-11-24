import XCTest
import simd
@testable import TraceAR

final class TraceStateAndFilterTests: XCTestCase {

    func testOpacityClampingAndCacheKeyIgnoresOpacity() {
        var settings = TraceFilterSettings()
        settings.opacity = 2.5
        XCTAssertEqual(settings.opacity, 1.0, accuracy: 0.0001)

        settings.opacity = -0.3
        XCTAssertEqual(settings.opacity, TraceFilterSettings.minOpacity, accuracy: 0.0001)
        XCTAssertFalse(settings.requiresImageProcessing)

        let id = UUID()
        var settingsA = TraceFilterSettings(opacity: 0.25, isOutlineOnly: true, isGrayscale: false, isInverted: false)
        let settingsB = TraceFilterSettings(opacity: 0.90, isOutlineOnly: true, isGrayscale: false, isInverted: false)

        let keyA = TraceFilterSettings.FilterCacheKey(sourceID: id, settings: settingsA)
        let keyB = TraceFilterSettings.FilterCacheKey(sourceID: id, settings: settingsB)
        XCTAssertEqual(keyA, keyB, "Changing opacity must not invalidate the Core Image filter cache")

        settingsA.isInverted = true
        let keyC = TraceFilterSettings.FilterCacheKey(sourceID: id, settings: settingsA)
        XCTAssertNotEqual(keyA, keyC)
    }

    func testStabilityMonitorPromptsReanchorAndRecovers() {
        var monitor = StabilityMonitor()
        monitor.beginPlaneScan(now: 100.0)
        monitor.markPlaneDetected()

        // Normal tracking while placed -> no prompt.
        monitor.update(quality: .normal, ambientIntensityLumens: 800, isAnchorPlaced: true, now: 101.0)
        XCTAssertFalse(monitor.shouldPromptReanchor)

        // Relocalizing begins at t=102 -> not prompted yet at t=104 (< 3s).
        monitor.update(quality: .limitedRelocalizing, ambientIntensityLumens: 800, isAnchorPlaced: true, now: 102.0)
        monitor.update(quality: .limitedRelocalizing, ambientIntensityLumens: 800, isAnchorPlaced: true, now: 104.0)
        XCTAssertFalse(monitor.shouldPromptReanchor)

        // Still relocalizing at t=105.2 (>= 3s) -> auto-prompts re-anchor.
        monitor.update(quality: .limitedRelocalizing, ambientIntensityLumens: 800, isAnchorPlaced: true, now: 105.2)
        XCTAssertTrue(monitor.shouldPromptReanchor)

        // Tracking recovers to normal -> prompt clears automatically.
        monitor.update(quality: .normal, ambientIntensityLumens: 800, isAnchorPlaced: true, now: 106.0)
        XCTAssertFalse(monitor.shouldPromptReanchor)
    }

    func testStabilityMonitorLowLightHysteresisAndPlaneTimeout() {
        var monitor = StabilityMonitor()
        monitor.beginPlaneScan(now: 10.0)

        // Dim room (280 lumens < 350 threshold) triggers low light.
        monitor.update(quality: .initializing, ambientIntensityLumens: 280, isAnchorPlaced: false, now: 12.0)
        XCTAssertTrue(monitor.isLowLight)
        XCTAssertFalse(monitor.isNoPlaneTimedOut)

        // 390 lumens stays in low-light state due to 420-lumen exit hysteresis.
        monitor.update(quality: .initializing, ambientIntensityLumens: 390, isAnchorPlaced: false, now: 15.0)
        XCTAssertTrue(monitor.isLowLight)

        // 450 lumens clears low-light warning; 8.5s without plane triggers no-plane timeout.
        monitor.update(quality: .initializing, ambientIntensityLumens: 450, isAnchorPlaced: false, now: 18.5)
        XCTAssertFalse(monitor.isLowLight)
        XCTAssertTrue(monitor.isNoPlaneTimedOut)
    }

    func testCoreImageProcessorOutlineGrayscaleAndInvertProduceCGImages() {
        let sample = SampleShapeGenerator.generate(.botanicalLeaf, dimension: 256)
        let id = UUID()

        let outlineSettings = TraceFilterSettings(opacity: 0.7, isOutlineOnly: true, isGrayscale: false, isInverted: false)
        let outlineCG = TraceImageProcessor.shared.process(source: sample, sourceID: id, settings: outlineSettings)
        XCTAssertNotNil(outlineCG)
        XCTAssertEqual(outlineCG?.width, 256)

        let grayInvertSettings = TraceFilterSettings(opacity: 0.7, isOutlineOnly: false, isGrayscale: true, isInverted: true)
        let grayInvertCG = TraceImageProcessor.shared.process(source: sample, sourceID: id, settings: grayInvertSettings)
        XCTAssertNotNil(grayInvertCG)
        XCTAssertEqual(grayInvertCG?.height, 256)
    }

    func testScreenAlignedTransformLookingStraightDownIsOrthonormal() {
        // Simulates iPhone flat on a glass stand looking straight down (-Y world).
        // Camera +X = (1, 0, 0), Camera +Y = (0, 0, -1), Camera +Z = (0, 1, 0)
        let straightDownCamera = simd_float4x4(
            SIMD4<Float>(1, 0, 0, 0),
            SIMD4<Float>(0, 0, -1, 0),
            SIMD4<Float>(0, 1, 0, 0),
            SIMD4<Float>(0, 0.25, 0, 1)
        )

        let anchorTransform = ARTraceViewContainer.Coordinator.makeScreenAlignedHorizontalTransform(
            position: SIMD3<Float>(0.05, 0.0, -0.02),
            cameraTransform: straightDownCamera
        )

        let x = SIMD3<Float>(anchorTransform.columns.0.x, anchorTransform.columns.0.y, anchorTransform.columns.0.z)
        let y = SIMD3<Float>(anchorTransform.columns.1.x, anchorTransform.columns.1.y, anchorTransform.columns.1.z)
        let z = SIMD3<Float>(anchorTransform.columns.2.x, anchorTransform.columns.2.y, anchorTransform.columns.2.z)

        XCTAssertEqual(simd_length(x), 1.0, accuracy: 0.001)
        XCTAssertEqual(simd_length(y), 1.0, accuracy: 0.001)
        XCTAssertEqual(simd_length(z), 1.0, accuracy: 0.001)
        XCTAssertEqual(simd_dot(x, y), 0.0, accuracy: 0.001)
        XCTAssertEqual(simd_dot(y, z), 0.0, accuracy: 0.001)
    }

    func testAllAppErrorStatesContainFriendlyCopyAndActions() {
        let states: [AppErrorState] = [
            .cameraPermissionDenied(),
            .photoSavePermissionDenied(),
            .arkitUnsupported(),
            .noPlaneFound(),
            .lowLight(),
            .trackingLimited(reason: "Hold steady"),
            .imageImportFailed(detail: "Corrupt image"),
            .saveFailed(detail: "Disk full"),
            .memoryWarning()
        ]

        for state in states {
            XCTAssertFalse(state.title.isEmpty)
            XCTAssertFalse(state.message.isEmpty)
            XCTAssertFalse(state.primaryAction.buttonTitle.isEmpty)
        }
    }
}
