import SwiftUI
import UIKit
import PhotosUI

struct ARTraceScreen: View {
    @ObservedObject var viewModel: ARSessionViewModel
    @Binding var keepScreenAwake: Bool
    let onSwitchToSketchPad: () -> Void
    let onOpenSettingsSheet: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isShowingReferencePicker = false
    @State private var sharePayload: ShareSheetPayload?
    @State private var quickPhotoItem: PhotosPickerItem?

    var body: some View {
        ZStack {
            if !viewModel.isARKitSupported {
                unsupportedOrPermissionFallback(
                    icon: "arkit",
                    title: "AR Tracking Not Available",
                    message: "This device or simulator doesn't support AR world tracking. Switch to Sketch Pad to draw and export offline.",
                    primaryTitle: "Open Sketch Pad",
                    primaryAction: onSwitchToSketchPad,
                    secondaryTitle: nil,
                    secondaryAction: nil
                )
            } else if viewModel.cameraAccess == .denied {
                unsupportedOrPermissionFallback(
                    icon: "video.slash.fill",
                    title: "Camera Access Turned Off",
                    message: "Enable Camera in iOS Settings so TraceAR can detect your paper and project your reference guide.",
                    primaryTitle: "Open Settings",
                    primaryAction: openSystemSettings,
                    secondaryTitle: "Use Sketch Pad",
                    secondaryAction: onSwitchToSketchPad
                )
            } else {
                ARTraceViewContainer(viewModel: viewModel)
                    .ignoresSafeArea()
            }

            VStack(spacing: 10) {
                topHUD

                if viewModel.stability.shouldPromptReanchor && viewModel.isPlaced {
                    ReanchorPromptCard(
                        onReanchor: { viewModel.reanchor() },
                        onDismiss: { viewModel.dismissReanchorPrompt() }
                    )
                    .padding(.horizontal, 16)
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                }

                if let errorState = viewModel.activeError,
                   viewModel.cameraAccess != .denied,
                   viewModel.isARKitSupported {
                    ErrorBannerView(errorState: errorState, onAction: handleErrorAction)
                        .padding(.horizontal, 16)
                        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                }

                if let statusText = viewModel.statusBannerText {
                    Text(statusText)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color.black.opacity(0.72)))
                        .accessibilityAddTraits(.isStaticText)
                        .transition(.opacity)
                }

                Spacer()

                if viewModel.cameraAccess == .authorized && viewModel.isARKitSupported {
                    if viewModel.referenceImage == nil {
                        emptyReferenceCard
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                    } else {
                        bottomControlPanel
                            .padding(.horizontal, 12)
                            .padding(.bottom, 8)
                    }
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: viewModel.activeError?.id)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: viewModel.stability.shouldPromptReanchor)
        }
        .sheet(isPresented: $isShowingReferencePicker) {
            ReferencePickerSheet(viewModel: viewModel)
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $sharePayload) { payload in
            ShareSheet(items: payload.items)
        }
        .onChange(of: quickPhotoItem) { newItem in
            guard let newItem else { return }
            loadQuickPhoto(newItem)
        }
    }

    // MARK: - Top HUD

    private var topHUD: some View {
        HStack(spacing: 8) {
            trackingQualityBadge

            Spacer(minLength: 4)

            Button {
                isShowingReferencePicker = true
            } label: {
                Image(systemName: "photo.on.rectangle")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel("Choose reference image")

            Menu {
                Button {
                    Task { await viewModel.saveARSnapshotToPhotos() }
                } label: {
                    Label("Save AR Snapshot to Photos", systemImage: "square.and.arrow.down")
                }

                Button {
                    if let snapshot = viewModel.captureARSnapshot() {
                        sharePayload = ShareSheetPayload(items: [snapshot])
                    }
                } label: {
                    Label("Share AR Snapshot…", systemImage: "square.and.arrow.up")
                }
            } label: {
                Image(systemName: "camera.fill")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel("Capture or share AR snapshot")

            Button(action: onOpenSettingsSheet) {
                Image(systemName: "gearshape.fill")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel("Open settings")
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
    }

    private var trackingQualityBadge: some View {
        let quality = viewModel.stability.quality
        let dotColor: Color = {
            switch quality.severity {
            case .good:
                return .green
            case .caution:
                return .yellow
            case .critical:
                return .red
            }
        }()

        return HStack(spacing: 8) {
            Circle()
                .fill(dotColor)
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)

            Text(quality.badgeTitle)
                .font(.footnote.weight(.semibold))

            if viewModel.stability.isLowLight {
                Image(systemName: "sun.min.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Low ambient light")
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 38)
        .background(.ultraThinMaterial, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("AR tracking status: \(quality.badgeTitle)\(viewModel.stability.isLowLight ? ", low light" : "")")
        .accessibilityHint(quality.guidanceMessage ?? "Surface tracking is stable.")
    }

    // MARK: - Empty State

    private var emptyReferenceCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "scribble.variable")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)

            Text("Choose an Image to Trace")
                .font(.headline)

            Text("Import a photo, paste from clipboard, or pick a built-in practice guide to project onto your paper.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 10) {
                PhotosPicker(selection: $quickPhotoItem, matching: .images, photoLibrary: .shared()) {
                    Label("Photos", systemImage: "photo")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.accentColor)
                        )
                        .foregroundStyle(.white)
                }

                Button {
                    isShowingReferencePicker = true
                } label: {
                    Label("Samples", systemImage: "cube.transparent")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(.tertiarySystemFill))
                        )
                        .foregroundStyle(.primary)
                }

                Button {
                    viewModel.pasteFromClipboard()
                } label: {
                    Image(systemName: "doc.on.clipboard")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 48, height: 46)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(.tertiarySystemFill))
                        )
                        .foregroundStyle(.primary)
                }
                .accessibilityLabel("Paste image from clipboard")
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.regularMaterial)
        )
    }

    // MARK: - Bottom One-Handed Control Panel

    private var bottomControlPanel: some View {
        VStack(spacing: 12) {
            if !viewModel.isPlaced {
                placementBar
            } else {
                placedControlsStack
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.regularMaterial)
        )
    }

    private var placementBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: viewModel.isReticleOnPlane ? "checkmark.circle.fill" : "viewfinder")
                    .foregroundStyle(viewModel.isReticleOnPlane ? .green : .secondary)
                    .accessibilityHidden(true)

                Text(
                    viewModel.isReticleOnPlane
                        ? "Paper surface detected — tap Place or tap directly on the paper"
                        : "Aim at well-lit paper and move gently to detect the surface"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                Button {
                    viewModel.placeOnDetectedSurface()
                } label: {
                    Label("Place on Surface", systemImage: "pin.fill")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.accentColor)
                        )
                }
                .accessibilityHint("Anchors your reference image onto the flat surface in the center of the camera view")

                Button {
                    isShowingReferencePicker = true
                } label: {
                    Image(systemName: "photo.on.rectangle")
                        .font(.body.weight(.semibold))
                        .frame(width: 50, height: 50)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color(.tertiarySystemFill))
                        )
                }
                .accessibilityLabel("Change reference image")
            }
        }
    }

    private var placedControlsStack: some View {
        VStack(spacing: 12) {
            // Row 1: Lock / Unlock + Re-anchor or Fine Nudge
            HStack(spacing: 8) {
                Button {
                    viewModel.toggleLock()
                } label: {
                    Label(
                        viewModel.isLocked ? "Locked" : "Lock Position",
                        systemImage: viewModel.isLocked ? "lock.fill" : "lock.open.fill"
                    )
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(viewModel.isLocked ? .black : .white)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 46)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(viewModel.isLocked ? Color.yellow : Color.accentColor)
                    )
                }
                .accessibilityLabel(viewModel.isLocked ? "Position locked. Tap to unlock and adjust" : "Lock image position on paper")

                if !viewModel.isLocked {
                    Button {
                        viewModel.nudgeScale(factor: 0.90)
                    } label: {
                        Image(systemName: "minus.magnifyingglass")
                            .frame(width: 44, height: 46)
                            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .accessibilityLabel("Shrink reference image, current scale \(viewModel.currentScalePercent) percent")

                    Button {
                        viewModel.nudgeScale(factor: 1.10)
                    } label: {
                        Image(systemName: "plus.magnifyingglass")
                            .frame(width: 44, height: 46)
                            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .accessibilityLabel("Enlarge reference image, current scale \(viewModel.currentScalePercent) percent")

                    Button {
                        viewModel.nudgeRotation(degrees: 15)
                    } label: {
                        Image(systemName: "rotate.right")
                            .frame(width: 44, height: 46)
                            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .accessibilityLabel("Rotate reference 15 degrees clockwise")
                }

                Button {
                    viewModel.reanchor()
                } label: {
                    Image(systemName: "scope")
                        .frame(width: 44, height: 46)
                        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
                }
                .accessibilityLabel("Re-anchor reference image on surface")
            }

            // Row 2: Opacity Slider (GPU-direct, 60 fps)
            HStack(spacing: 10) {
                Image(systemName: "circle.dotted")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                Slider(
                    value: Binding(
                        get: { viewModel.filterSettings.opacity },
                        set: { viewModel.setOpacity($0) }
                    ),
                    in: TraceFilterSettings.minOpacity...TraceFilterSettings.maxOpacity
                )
                .accessibilityLabel("Overlay opacity")
                .accessibilityValue("\(Int((viewModel.filterSettings.opacity * 100).rounded())) percent")

                Text("\(Int((viewModel.filterSettings.opacity * 100).rounded()))%")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .frame(width: 42, alignment: .trailing)
                    .accessibilityHidden(true)
            }

            // Row 3: Trace Filter Chips (Outline, Grayscale, Invert)
            HStack(spacing: 8) {
                filterChip(
                    title: "Outline",
                    icon: "scribble",
                    isActive: viewModel.filterSettings.isOutlineOnly,
                    action: viewModel.toggleOutlineOnly
                )

                filterChip(
                    title: "Grayscale",
                    icon: "circle.lefthalf.filled",
                    isActive: viewModel.filterSettings.isGrayscale,
                    isDisabled: viewModel.filterSettings.isOutlineOnly,
                    action: viewModel.toggleGrayscale
                )

                filterChip(
                    title: "Invert",
                    icon: "circle.righthalf.filled",
                    isActive: viewModel.filterSettings.isInverted,
                    action: viewModel.toggleInvert
                )
            }
        }
    }

    private func filterChip(
        title: String,
        icon: String,
        isActive: Bool,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.footnote.weight(.semibold))
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isActive ? Color.accentColor : Color(.tertiarySystemFill))
            )
            .foregroundStyle(isActive ? .white : .primary)
            .opacity(isDisabled ? 0.45 : 1.0)
        }
        .disabled(isDisabled)
        .accessibilityLabel("\(title) filter")
        .accessibilityValue(isActive ? "On" : "Off")
    }

    // MARK: - Fallback State & Error Actions

    private func unsupportedOrPermissionFallback(
        icon: String,
        title: String,
        message: String,
        primaryTitle: String,
        primaryAction: @escaping () -> Void,
        secondaryTitle: String?,
        secondaryAction: (() -> Void)?
    ) -> some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 52, weight: .semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text(title)
                .font(.title3.bold())
                .multilineTextAlignment(.center)

            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            VStack(spacing: 12) {
                Button(action: primaryAction) {
                    Text(primaryTitle)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: 280, minHeight: 50)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
                }

                if let secondaryTitle, let secondaryAction {
                    Button(action: secondaryAction) {
                        Text(secondaryTitle)
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: 280, minHeight: 46)
                            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                    }
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground).ignoresSafeArea())
    }

    private func handleErrorAction(_ action: AppErrorAction) {
        switch action {
        case .openSettings:
            openSystemSettings()
        case .switchToSketchPad:
            viewModel.dismissError()
            onSwitchToSketchPad()
        case .retryPlaneScan:
            viewModel.retrySurfaceScan()
        case .placeAtFallbackDepth:
            viewModel.placeAtFallbackStandDistance()
        case .reanchorImage:
            viewModel.dismissError()
            viewModel.reanchor()
        case .openSampleShapes:
            viewModel.dismissError()
            isShowingReferencePicker = true
        case .shareInstead:
            viewModel.dismissError()
            if let image = viewModel.pendingShareImage ?? viewModel.captureARSnapshot() {
                sharePayload = ShareSheetPayload(items: [image])
            }
        case .resetFilters:
            viewModel.dismissError()
            viewModel.resetFilters()
        case .dismiss:
            viewModel.dismissError()
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func loadQuickPhoto(_ item: PhotosPickerItem) {
        Task {
            do {
                if let data = try await item.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data) {
                    await MainActor.run {
                        viewModel.importRawImage(uiImage)
                    }
                } else {
                    await MainActor.run {
                        viewModel.handleImageImportFailure(
                            "Couldn't decode that photo. Try another image or select a built-in sample shape."
                        )
                    }
                }
            } catch {
                await MainActor.run {
                    viewModel.handleImageImportFailure(
                        "Failed to load photo (\(error.localizedDescription))."
                    )
                }
            }
        }
    }
}
