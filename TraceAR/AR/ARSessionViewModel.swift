import SwiftUI
import UIKit
import AVFoundation
import ARKit

@MainActor
protocol ARSceneControlling: AnyObject {
    func placeReferenceAtScreenCenter() -> Bool
    func placeReferenceAtFallbackDistance() -> Bool
    func removePlacedAnchor()
    func updateOverlayTexture(_ cgImage: CGImage?, aspectRatio: CGFloat)
    func updateOverlayOpacity(_ opacity: Double)
    func setAnchorLocked(_ isLocked: Bool)
    func nudgeScale(by factor: Float)
    func nudgeRotation(by radians: Float)
    func resetManipulableTransform()
    func restartPlaneDetection(resetTracking: Bool)
    func pauseSession()
    func resumeSession(planeDetectionEnabled: Bool)
    func captureSnapshot() -> UIImage?
}

@MainActor
final class ARSessionViewModel: ObservableObject {
    enum CameraAccessState: Equatable {
        case unknown
        case authorized
        case denied
    }

    @Published private(set) var cameraAccess: CameraAccessState = .unknown
    @Published private(set) var isARKitSupported: Bool = ARWorldTrackingConfiguration.isSupported

    @Published private(set) var referenceImage: UIImage?
    @Published private(set) var referenceID: UUID = UUID()
    @Published private(set) var processedCGImage: CGImage?
    @Published private(set) var isProcessingFilter: Bool = false

    @Published var filterSettings = TraceFilterSettings()

    @Published private(set) var isPlaced: Bool = false
    @Published private(set) var isLocked: Bool = false
    @Published private(set) var currentScalePercent: Int = 100
    @Published private(set) var isReticleOnPlane: Bool = false

    @Published private(set) var stability = StabilityMonitor()
    @Published var activeError: AppErrorState?
    @Published var statusBannerText: String?

    /// Last captured/rendered image available for fallback sharing if Photos permission is denied.
    @Published var pendingShareImage: UIImage?

    weak var sceneController: ARSceneControlling?
    var onMemoryWarningCleanup: (() -> Void)?

    private var filterTask: Task<Void, Never>?
    private var lastAppliedFilterKey: TraceFilterSettings.FilterCacheKey?
    private var lowLightBannerDismissed: Bool = false
    private var isARScreenVisible: Bool = false

    init() {
        refreshCameraAuthorizationState()
    }

    var referenceAspectRatio: CGFloat {
        guard let img = referenceImage, img.size.height > 0 else { return 1.0 }
        return img.size.width / img.size.height
    }

    // MARK: - Permissions & Lifecycle

    func refreshCameraAuthorizationState() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            cameraAccess = .authorized
        case .notDetermined:
            cameraAccess = .unknown
        case .denied, .restricted:
            cameraAccess = .denied
        @unknown default:
            cameraAccess = .denied
        }
    }

    func prepareARSessionIfPermitted() async {
        isARScreenVisible = true

        guard isARKitSupported else {
            activeError = .arkitUnsupported()
            return
        }

        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            cameraAccess = .authorized
            startOrResumeTracking()
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            cameraAccess = granted ? .authorized : .denied
            if granted {
                startOrResumeTracking()
            } else {
                activeError = .cameraPermissionDenied()
            }
        case .denied, .restricted:
            cameraAccess = .denied
            activeError = .cameraPermissionDenied()
        @unknown default:
            cameraAccess = .denied
            activeError = .cameraPermissionDenied()
        }
    }

    func handleScenePhaseChange(_ phase: ScenePhase, isCurrentModeAR: Bool, keepScreenAwake: Bool) {
        switch phase {
        case .active:
            refreshCameraAuthorizationState()
            if isCurrentModeAR {
                isARScreenVisible = true
                updateIdleTimer(keepAwake: keepScreenAwake, active: true)
                if cameraAccess == .authorized && isARKitSupported {
                    sceneController?.resumeSession(planeDetectionEnabled: !isLocked)
                }
            } else {
                updateIdleTimer(keepAwake: false, active: false)
            }
        case .inactive:
            updateIdleTimer(keepAwake: false, active: false)
        case .background:
            updateIdleTimer(keepAwake: false, active: false)
            sceneController?.pauseSession()
        @unknown default:
            break
        }
    }

    func setARModeActive(_ active: Bool, keepScreenAwake: Bool) {
        isARScreenVisible = active
        if active {
            updateIdleTimer(keepAwake: keepScreenAwake, active: true)
            Task {
                await prepareARSessionIfPermitted()
            }
        } else {
            updateIdleTimer(keepAwake: false, active: false)
            sceneController?.pauseSession()
        }
    }

    func updateIdleTimer(keepAwake: Bool, active: Bool) {
        UIApplication.shared.isIdleTimerDisabled = active && keepAwake
    }

    private func startOrResumeTracking() {
        if case .cameraPermissionDenied = activeError?.kind {
            activeError = nil
        }
        stability.beginPlaneScan(now: ProcessInfo.processInfo.systemUptime)
        sceneController?.resumeSession(planeDetectionEnabled: !isLocked)
    }

    // MARK: - Reference Image Import & Filtering

    func importRawImage(_ rawImage: UIImage) {
        let currentSettings = filterSettings
        isProcessingFilter = true

        Task.detached(priority: .userInitiated) { [weak self] in
            let normalized = TraceImageProcessor.shared.normalizeAndDownsample(rawImage)
            let newID = UUID()
            let processed = TraceImageProcessor.shared.process(
                source: normalized,
                sourceID: newID,
                settings: currentSettings
            )

            await MainActor.run {
                guard let self else { return }
                self.referenceImage = normalized
                self.referenceID = newID
                self.processedCGImage = processed
                self.lastAppliedFilterKey = TraceFilterSettings.FilterCacheKey(
                    sourceID: newID,
                    settings: currentSettings
                )
                self.isProcessingFilter = false
                self.sceneController?.updateOverlayTexture(
                    processed,
                    aspectRatio: self.referenceAspectRatio
                )
                self.sceneController?.updateOverlayOpacity(currentSettings.opacity)
                HapticsManager.notifySuccess()
            }
        }
    }

    func selectSampleShape(_ kind: SampleShapeKind) {
        let image = SampleShapeGenerator.generate(kind)
        importRawImage(image)
        showTransientStatus("Loaded \"\(kind.title)\"")
    }

    func pasteFromClipboard() {
        let pasteboard = UIPasteboard.general
        if let image = pasteboard.image {
            importRawImage(image)
            showTransientStatus("Pasted image from clipboard")
            return
        }
        for uti in ["public.png", "public.jpeg", "public.tiff"] {
            if let data = pasteboard.data(forPasteboardType: uti),
               let decoded = UIImage(data: data) {
                importRawImage(decoded)
                showTransientStatus("Pasted image from clipboard")
                return
            }
        }
        HapticsManager.notifyWarning()
        activeError = .imageImportFailed(
            detail: "Your clipboard doesn't contain an image yet. Copy a picture from Photos or Safari first, or try a Sample Shape."
        )
    }

    func handleImageImportFailure(_ message: String) {
        HapticsManager.notifyWarning()
        activeError = .imageImportFailed(detail: message)
    }

    func setOpacity(_ value: Double) {
        filterSettings.opacity = value
        sceneController?.updateOverlayOpacity(filterSettings.opacity)
    }

    func toggleOutlineOnly() {
        filterSettings.isOutlineOnly.toggle()
        HapticsManager.lightTap()
        reapplyFiltersIfNeeded()
    }

    func toggleGrayscale() {
        filterSettings.isGrayscale.toggle()
        HapticsManager.lightTap()
        reapplyFiltersIfNeeded()
    }

    func toggleInvert() {
        filterSettings.isInverted.toggle()
        HapticsManager.lightTap()
        reapplyFiltersIfNeeded()
    }

    func resetFilters() {
        filterSettings.reset()
        sceneController?.updateOverlayOpacity(filterSettings.opacity)
        reapplyFiltersIfNeeded()
    }

    private func reapplyFiltersIfNeeded() {
        guard let source = referenceImage else { return }
        let sourceID = referenceID
        let settings = filterSettings
        let key = TraceFilterSettings.FilterCacheKey(sourceID: sourceID, settings: settings)
        if key == lastAppliedFilterKey {
            return
        }

        filterTask?.cancel()
        isProcessingFilter = true

        filterTask = Task.detached(priority: .userInitiated) { [weak self] in
            let cgImg = TraceImageProcessor.shared.process(
                source: source,
                sourceID: sourceID,
                settings: settings
            )
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self else { return }
                self.processedCGImage = cgImg
                self.lastAppliedFilterKey = key
                self.isProcessingFilter = false
                self.sceneController?.updateOverlayTexture(cgImg, aspectRatio: self.referenceAspectRatio)
            }
        }
    }

    // MARK: - Placement, Manipulation & Locking

    func placeOnDetectedSurface() {
        guard referenceImage != nil else { return }
        guard let controller = sceneController else { return }

        if controller.placeReferenceAtScreenCenter() {
            didCompletePlacement()
        } else {
            HapticsManager.notifyWarning()
            activeError = .noPlaneFound()
        }
    }

    func placeAtFallbackStandDistance() {
        guard referenceImage != nil else { return }
        guard let controller = sceneController else { return }

        if controller.placeReferenceAtFallbackDistance() {
            didCompletePlacement()
            showTransientStatus("Placed 25 cm ahead — pinch or drag to adjust")
        }
    }

    func notifyPlacedViaTap() {
        didCompletePlacement()
    }

    private func didCompletePlacement() {
        isPlaced = true
        isLocked = false
        currentScalePercent = 100
        if case .noPlaneFound = activeError?.kind {
            activeError = nil
        }
        HapticsManager.placeImpact()
    }

    func toggleLock() {
        guard isPlaced else { return }
        isLocked.toggle()
        sceneController?.setAnchorLocked(isLocked)
        HapticsManager.lockChanged(isLocked: isLocked)
        showTransientStatus(isLocked ? "Position locked for tracing" : "Unlocked — drag, pinch, or rotate")
    }

    func reanchor() {
        isPlaced = false
        isLocked = false
        currentScalePercent = 100
        stability.resetForReanchor(now: ProcessInfo.processInfo.systemUptime)
        sceneController?.removePlacedAnchor()
        sceneController?.restartPlaneDetection(resetTracking: false)
        HapticsManager.lightTap()
    }

    func retrySurfaceScan() {
        isPlaced = false
        isLocked = false
        stability.resetForReanchor(now: ProcessInfo.processInfo.systemUptime)
        if case .noPlaneFound = activeError?.kind {
            activeError = nil
        }
        sceneController?.restartPlaneDetection(resetTracking: true)
        HapticsManager.lightTap()
    }

    func nudgeScale(factor: Float) {
        guard isPlaced, !isLocked else { return }
        sceneController?.nudgeScale(by: factor)
        HapticsManager.lightTap()
    }

    func nudgeRotation(degrees: Float) {
        guard isPlaced, !isLocked else { return }
        let radians = degrees * .pi / 180.0
        sceneController?.nudgeRotation(by: radians)
        HapticsManager.lightTap()
    }

    func resetTransform() {
        guard isPlaced, !isLocked else { return }
        sceneController?.resetManipulableTransform()
        currentScalePercent = 100
        HapticsManager.lightTap()
    }

    func didUpdateScale(_ scale: Float) {
        currentScalePercent = max(10, Int((scale * 100).rounded()))
    }

    // MARK: - Telemetry & Stability Callbacks (Throttled from Coordinator)

    func markPlaneDetected() {
        stability.markPlaneDetected()
        if case .noPlaneFound = activeError?.kind {
            activeError = nil
        }
    }

    func receiveFrameTelemetry(
        quality: TrackingQuality,
        ambientLumens: CGFloat?,
        reticleHitsPlane: Bool
    ) {
        if isReticleOnPlane != reticleHitsPlane {
            isReticleOnPlane = reticleHitsPlane
        }
        if reticleHitsPlane && !stability.hasDetectedPlane {
            stability.markPlaneDetected()
        }

        let previousLowLight = stability.isLowLight
        let previousTimeout = stability.isNoPlaneTimedOut

        stability.update(
            quality: quality,
            ambientIntensityLumens: ambientLumens,
            isAnchorPlaced: isPlaced,
            now: ProcessInfo.processInfo.systemUptime
        )

        if !stability.isLowLight {
            lowLightBannerDismissed = false
            if case .lowLight = activeError?.kind {
                activeError = nil
            }
        } else if !previousLowLight && !lowLightBannerDismissed && activeError == nil {
            activeError = .lowLight()
        }

        if stability.isNoPlaneTimedOut && !previousTimeout && referenceImage != nil && !isPlaced && activeError == nil {
            activeError = .noPlaneFound()
        }
    }

    func dismissReanchorPrompt() {
        stability.dismissReanchorPrompt()
    }

    func dismissError() {
        if case .lowLight = activeError?.kind {
            lowLightBannerDismissed = true
        }
        activeError = nil
    }

    // MARK: - Snapshot & Export

    func captureARSnapshot() -> UIImage? {
        guard let image = sceneController?.captureSnapshot() else {
            activeError = .saveFailed(detail: "Couldn't capture the AR camera frame. Ensure the camera view is active.")
            return nil
        }
        pendingShareImage = image
        HapticsManager.lightTap()
        return image
    }

    func saveARSnapshotToPhotos() async {
        guard let snapshot = captureARSnapshot() else { return }
        let result = await PhotoLibraryService.saveImageToPhotos(snapshot)
        switch result {
        case .success:
            HapticsManager.notifySuccess()
            showTransientStatus("Saved AR snapshot to Photos")
        case .failure(let errorState):
            HapticsManager.notifyWarning()
            activeError = errorState
        }
    }

    // MARK: - Memory Warning

    func handleMemoryWarning() {
        TraceImageProcessor.shared.purgeCache()
        lastAppliedFilterKey = nil
        onMemoryWarningCleanup?()
        if isARScreenVisible {
            activeError = .memoryWarning()
        }
    }

    func showTransientStatus(_ message: String) {
        statusBannerText = message
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if self?.statusBannerText == message {
                self?.statusBannerText = nil
            }
        }
    }
}
