import SwiftUI
import UIKit

struct SketchPadScreen: View {
    @ObservedObject var sketchVM: SketchCanvasViewModel
    let referenceImage: UIImage?
    let onOpenSettings: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var canvasSize: CGSize = CGSize(width: 360, height: 480)
    @State private var activeError: AppErrorState?
    @State private var statusMessage: String?
    @State private var sharePayload: ShareSheetPayload?
    @State private var lastRenderedExport: UIImage?
    @State private var showClearConfirmation: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            topActionBar
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.systemBackground))

            ZStack {
                drawingPaperArea

                VStack(spacing: 8) {
                    if let error = activeError {
                        ErrorBannerView(errorState: error, onAction: handleErrorAction)
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                    }

                    if let status = statusMessage {
                        Text(status)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(Color.black.opacity(0.75)))
                            .padding(.top, 8)
                            .transition(.opacity)
                    }

                    Spacer()
                }
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: activeError?.id)
            }

            bottomToolPalette
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    Color(.secondarySystemBackground)
                        .shadow(color: .black.opacity(0.08), radius: 6, y: -2)
                )
        }
        .sheet(item: $sharePayload) { payload in
            ShareSheet(items: payload.items)
        }
        .confirmationDialog(
            "Clear Sketch Canvas?",
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear All Strokes", role: .destructive) {
                sketchVM.clearCanvas()
                HapticsManager.lightTap()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You can still tap Undo right after clearing if you change your mind.")
        }
    }

    // MARK: - Top Bar (Undo / Redo / Clear / Save / Share / Settings)

    private var topActionBar: some View {
        HStack(spacing: 6) {
            Button {
                sketchVM.undo()
                HapticsManager.lightTap()
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .background(Color(.secondarySystemBackground), in: Circle())
            }
            .disabled(!sketchVM.canUndo)
            .opacity(sketchVM.canUndo ? 1.0 : 0.38)
            .accessibilityLabel("Undo stroke")

            Button {
                sketchVM.redo()
                HapticsManager.lightTap()
            } label: {
                Image(systemName: "arrow.uturn.forward")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .background(Color(.secondarySystemBackground), in: Circle())
            }
            .disabled(!sketchVM.canRedo)
            .opacity(sketchVM.canRedo ? 1.0 : 0.38)
            .accessibilityLabel("Redo stroke")

            Button {
                showClearConfirmation = true
            } label: {
                Image(systemName: "trash")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .background(Color(.secondarySystemBackground), in: Circle())
            }
            .disabled(sketchVM.isEmpty)
            .opacity(sketchVM.isEmpty ? 0.38 : 1.0)
            .accessibilityLabel("Clear canvas")

            Spacer(minLength: 4)

            if referenceImage != nil {
                Button {
                    sketchVM.showReferenceUnderlay.toggle()
                    HapticsManager.lightTap()
                } label: {
                    Image(systemName: sketchVM.showReferenceUnderlay ? "eye.fill" : "eye.slash")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(sketchVM.showReferenceUnderlay ? Color.accentColor : .primary)
                        .frame(width: 44, height: 44)
                        .background(Color(.secondarySystemBackground), in: Circle())
                }
                .accessibilityLabel(sketchVM.showReferenceUnderlay ? "Hide reference guide underlay" : "Show faint reference guide underlay")
            }

            Button {
                Task { await saveSketchToPhotos() }
            } label: {
                Image(systemName: "square.and.arrow.down")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .background(Color(.secondarySystemBackground), in: Circle())
            }
            .accessibilityLabel("Save sketch to Photos")

            Button {
                shareCurrentSketch()
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .background(Color(.secondarySystemBackground), in: Circle())
            }
            .accessibilityLabel("Share sketch")

            Button(action: onOpenSettings) {
                Image(systemName: "gearshape.fill")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .background(Color(.secondarySystemBackground), in: Circle())
            }
            .accessibilityLabel("Open settings")
        }
    }

    // MARK: - Drawing Canvas

    private var drawingPaperArea: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                Color.white

                if let referenceImage, sketchVM.showReferenceUnderlay {
                    Image(uiImage: referenceImage)
                        .resizable()
                        .scaledToFit()
                        .padding(16)
                        .opacity(sketchVM.underlayOpacity)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }

                if sketchVM.isEmpty && !sketchVM.showReferenceUnderlay {
                    VStack(spacing: 8) {
                        Image(systemName: "hand.draw")
                            .font(.system(size: 30))
                            .foregroundStyle(Color.gray.opacity(0.45))
                        Text("Sketch freely with finger or stylus")
                            .font(.footnote)
                            .foregroundStyle(Color.gray.opacity(0.65))
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }

                Canvas(opaque: false, colorMode: .linear, rendersAsynchronously: false) { context, _ in
                    // Isolated sublayer ensures destinationOut erasing affects only ink, never paper or underlay.
                    context.drawLayer { inkLayer in
                        for stroke in sketchVM.strokes {
                            drawStroke(stroke, in: &inkLayer)
                        }
                        if let active = sketchVM.activeStroke {
                            drawStroke(active, in: &inkLayer)
                        }
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .local)
                        .onChanged { value in
                            let clamped = CGPoint(
                                x: min(max(0, value.location.x), size.width),
                                y: min(max(0, value.location.y), size.height)
                            )
                            if sketchVM.activeStroke == nil {
                                sketchVM.beginStroke(at: clamped)
                            } else {
                                sketchVM.appendPoint(clamped)
                            }
                        }
                        .onEnded { _ in
                            sketchVM.endStroke()
                        }
                )
                .accessibilityElement()
                .accessibilityLabel("Drawing canvas, \(sketchVM.strokes.count) strokes")
                .accessibilityHint("Drag with one finger to draw using the selected \(sketchVM.selectedTool.rawValue.lowercased()) tool.")
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color(.separator), lineWidth: 1)
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .onAppear {
                if size.width > 10 && size.height > 10 {
                    canvasSize = size
                }
            }
            .onChange(of: size) { newSize in
                if newSize.width > 10 && newSize.height > 10 {
                    canvasSize = newSize
                }
            }
        }
    }

    private func drawStroke(_ stroke: SketchStroke, in context: inout GraphicsContext) {
        guard !stroke.points.isEmpty else { return }
        let path = SketchRenderer.buildSwiftUIPath(points: stroke.points)
        let style = StrokeStyle(
            lineWidth: stroke.effectiveLineWidth,
            lineCap: .round,
            lineJoin: .round
        )

        switch stroke.tool {
        case .pencil:
            context.blendMode = .normal
            context.stroke(path, with: .color(stroke.color.swiftUIColor), style: style)
        case .eraser:
            context.blendMode = .destinationOut
            context.stroke(path, with: .color(.black), style: style)
        }
    }

    // MARK: - Bottom Palette (Tools, 3 Sizes, 6 Colors)

    private var bottomToolPalette: some View {
        VStack(spacing: 10) {
            // Row 1: Pencil / Eraser + 3 Brush Sizes
            HStack(spacing: 8) {
                ForEach(SketchTool.allCases) { tool in
                    let isSelected = (sketchVM.selectedTool == tool)
                    Button {
                        sketchVM.selectedTool = tool
                        HapticsManager.lightTap()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: tool.systemImage)
                                .font(.footnote.weight(.semibold))
                            Text(tool.rawValue)
                                .font(.footnote.weight(.semibold))
                        }
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(isSelected ? Color.accentColor : Color(.tertiarySystemFill))
                        )
                        .foregroundStyle(isSelected ? .white : .primary)
                    }
                    .accessibilityLabel("\(tool.rawValue) tool")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }

                Spacer(minLength: 4)

                HStack(spacing: 6) {
                    ForEach(BrushSizePreset.allCases) { preset in
                        let isSelected = (sketchVM.selectedSize == preset)
                        Button {
                            sketchVM.selectedSize = preset
                            HapticsManager.lightTap()
                        } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(isSelected ? Color.accentColor.opacity(0.20) : Color(.tertiarySystemFill))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
                                    )

                                Circle()
                                    .fill(Color.primary)
                                    .frame(width: preset.pointWidth + 2, height: preset.pointWidth + 2)
                            }
                            .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel(preset.accessibilityName)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
            }

            // Row 2: 6 Color Swatches
            HStack(spacing: 10) {
                ForEach(SketchColorChoice.allCases) { choice in
                    let isSelected = (sketchVM.selectedColor == choice && sketchVM.selectedTool == .pencil)
                    Button {
                        sketchVM.selectedColor = choice
                        sketchVM.selectedTool = .pencil
                        HapticsManager.lightTap()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(choice.swiftUIColor)
                                .frame(width: 34, height: 34)

                            if isSelected {
                                Circle()
                                    .strokeBorder(Color.primary, lineWidth: 3)
                                    .frame(width: 42, height: 42)
                                Image(systemName: "checkmark")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .accessibilityLabel(choice.displayName)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
    }

    // MARK: - Save & Share Actions

    private func renderExportImage() -> UIImage? {
        SketchRenderer.renderImage(
            strokes: sketchVM.strokes,
            canvasSize: canvasSize,
            scale: 2.0,
            paperColor: .white,
            underlayImage: sketchVM.showReferenceUnderlay ? referenceImage : nil,
            underlayOpacity: sketchVM.showReferenceUnderlay ? CGFloat(sketchVM.underlayOpacity) : 0.0
        )
    }

    private func saveSketchToPhotos() async {
        guard let rendered = renderExportImage() else {
            activeError = .saveFailed(detail: "Canvas isn't ready to export yet. Try drawing a stroke first.")
            return
        }
        lastRenderedExport = rendered
        let result = await PhotoLibraryService.saveImageToPhotos(rendered)
        switch result {
        case .success:
            HapticsManager.notifySuccess()
            showTemporaryStatus("Saved sketch to Photos")
        case .failure(let err):
            HapticsManager.notifyWarning()
            activeError = err
        }
    }

    private func shareCurrentSketch() {
        guard let rendered = renderExportImage() else {
            activeError = .saveFailed(detail: "Couldn't prepare the sketch image for sharing.")
            return
        }
        lastRenderedExport = rendered
        HapticsManager.lightTap()
        if let fileURL = PhotoLibraryService.writeTemporaryPNG(rendered, filenamePrefix: "TraceAR-Sketch") {
            sharePayload = ShareSheetPayload(items: [fileURL])
        } else {
            sharePayload = ShareSheetPayload(items: [rendered])
        }
    }

    private func handleErrorAction(_ action: AppErrorAction) {
        switch action {
        case .openSettings:
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        case .shareInstead:
            activeError = nil
            if let image = lastRenderedExport ?? renderExportImage() {
                sharePayload = ShareSheetPayload(items: [image])
            }
        default:
            activeError = nil
        }
    }

    private func showTemporaryStatus(_ message: String) {
        statusMessage = message
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if statusMessage == message {
                statusMessage = nil
            }
        }
    }
}
