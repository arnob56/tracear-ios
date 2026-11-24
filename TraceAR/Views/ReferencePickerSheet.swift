import SwiftUI
import UIKit
import PhotosUI

struct ReferencePickerSheet: View {
    @ObservedObject var viewModel: ARSessionViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isLoadingPhoto: Bool = false

    private let gridColumns = [
        GridItem(.adaptive(minimum: 145), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    importSourcesSection
                    sampleShapesSection
                }
                .padding(16)
            }
            .navigationTitle("Choose Reference")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                    .frame(minWidth: 44, minHeight: 44)
                }
            }
            .overlay {
                if isLoadingPhoto {
                    ZStack {
                        Color.black.opacity(0.25).ignoresSafeArea()
                        ProgressView("Importing Photo…")
                            .padding(20)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
            }
            .onChange(of: selectedPhotoItem) { newItem in
                guard let newItem else { return }
                loadPhotoItem(newItem)
            }
        }
    }

    private var importSourcesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Import Your Own")
                .font(.headline)

            PhotosPicker(selection: $selectedPhotoItem, matching: .images, photoLibrary: .shared()) {
                HStack(spacing: 14) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 36, height: 36)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Choose from Photos")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("Select any portrait, object, or sketch from your library")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(14)
                .frame(minHeight: 56)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )
            }
            .accessibilityLabel("Choose reference image from Photos")

            Button {
                viewModel.pasteFromClipboard()
                if viewModel.activeError == nil {
                    dismiss()
                } else {
                    dismiss()
                }
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.teal)
                        .frame(width: 36, height: 36)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Paste from Clipboard")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("Use an image you copied from Photos, Files, or Safari")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(14)
                .frame(minHeight: 56)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )
            }
            .accessibilityLabel("Paste reference image from clipboard")
        }
    }

    private var sampleShapesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Built-In Practice Guides")
                .font(.headline)

            LazyVGrid(columns: gridColumns, spacing: 12) {
                ForEach(SampleShapeKind.allCases) { sample in
                    Button {
                        viewModel.selectSampleShape(sample)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: sample.systemIcon)
                                    .font(.title2)
                                    .foregroundStyle(Color.accentColor)
                                Spacer()
                            }
                            .frame(height: 36)

                            Text(sample.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)

                            Text(sample.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color(.secondarySystemBackground))
                        )
                    }
                    .accessibilityLabel("\(sample.title). \(sample.subtitle)")
                }
            }
        }
    }

    private func loadPhotoItem(_ item: PhotosPickerItem) {
        isLoadingPhoto = true
        Task {
            do {
                if let data = try await item.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data) {
                    await MainActor.run {
                        isLoadingPhoto = false
                        viewModel.importRawImage(uiImage)
                        dismiss()
                    }
                } else {
                    await MainActor.run {
                        isLoadingPhoto = false
                        viewModel.handleImageImportFailure(
                            "That photo format couldn't be decoded. Try another photo or choose a built-in sample shape."
                        )
                        dismiss()
                    }
                }
            } catch {
                await MainActor.run {
                    isLoadingPhoto = false
                    viewModel.handleImageImportFailure(
                        "Photo import failed (\(error.localizedDescription)). Check iCloud download status or pick another image."
                    )
                    dismiss()
                }
            }
        }
    }
}
