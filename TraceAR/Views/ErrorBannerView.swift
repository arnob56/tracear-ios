import SwiftUI

struct ErrorBannerView: View {
    let errorState: AppErrorState
    let onAction: (AppErrorAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: errorState.iconName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.orange)
                    .frame(width: 28, height: 28)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(errorState.title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)

                    Text(errorState.message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                Button {
                    onAction(errorState.primaryAction)
                } label: {
                    Text(errorState.primaryAction.buttonTitle)
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.accentColor)
                        )
                        .foregroundStyle(.white)
                }

                if let secondary = errorState.secondaryAction {
                    Button {
                        onAction(secondary)
                    } label: {
                        Text(secondary.buttonTitle)
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 14)
                            .frame(minHeight: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color(.tertiarySystemFill))
                            )
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        )
        .accessibilityElement(children: .contain)
    }
}

struct ReanchorPromptCard: View {
    let onReanchor: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.triangle.2.circlepath.camera.fill")
                    .font(.title3)
                    .foregroundStyle(.yellow)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Surface Tracking Drifted")
                        .font(.subheadline.bold())
                    Text("Re-anchor your reference image on the paper so lines line up accurately.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 10) {
                Button(action: onReanchor) {
                    Label("Re-anchor Now", systemImage: "scope")
                        .font(.footnote.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.accentColor)
                        )
                        .foregroundStyle(.white)
                }

                Button(action: onDismiss) {
                    Text("Wait")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 16)
                        .frame(minHeight: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(.tertiarySystemFill))
                        )
                        .foregroundStyle(.primary)
                }
                .accessibilityLabel("Dismiss re-anchor prompt")
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.20), radius: 10, y: 4)
        )
        .accessibilityElement(children: .contain)
    }
}
