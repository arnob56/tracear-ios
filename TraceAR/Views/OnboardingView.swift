import SwiftUI

struct OnboardingView: View {
    let onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var currentPage: Int = 0

    private struct StepItem: Identifiable {
        let id: Int
        let icon: String
        let accentColor: Color
        let title: String
        let bodyText: String
        let tipText: String
    }

    private let steps: [StepItem] = [
        StepItem(
            id: 0,
            icon: "iphone",
            accentColor: .teal,
            title: "1. Rest Phone on a Stand",
            bodyText: "Prop your iPhone 20–30 cm above your sketch paper using a tall glass, mug, stack of books, or phone stand.",
            tipText: "Good desk lighting helps the camera keep your paper steady."
        ),
        StepItem(
            id: 1,
            icon: "viewfinder",
            accentColor: .blue,
            title: "2. Anchor & Lock Your Guide",
            bodyText: "Pick a photo, sample shape, or clipboard image. Tap Place on Surface, pinch or twist to size it on your paper, then tap Lock.",
            tipText: "Once locked, accidental touches won't shift your drawing guide."
        ),
        StepItem(
            id: 2,
            icon: "scribble.variable",
            accentColor: .indigo,
            title: "3. Trace Smoothly Offline",
            bodyText: "Slide opacity or enable Outline mode so your pencil strokes stay clear. Everything runs 100% offline with no ads or accounts.",
            tipText: "You can also practice directly on screen in Sketch Pad anytime."
        )
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button(action: completeOnboarding) {
                    Text("Skip")
                        .font(.body.weight(.semibold))
                        .padding(.horizontal, 16)
                        .frame(minWidth: 64, minHeight: 44)
                }
                .accessibilityLabel("Skip onboarding guide")
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            TabView(selection: $currentPage) {
                ForEach(steps) { step in
                    ScrollView {
                        VStack(spacing: 24) {
                            Spacer(minLength: 20)

                            ZStack {
                                Circle()
                                    .fill(step.accentColor.opacity(0.15))
                                    .frame(width: 128, height: 128)
                                Image(systemName: step.icon)
                                    .font(.system(size: 52, weight: .semibold))
                                    .foregroundStyle(step.accentColor)
                                    .accessibilityHidden(true)
                            }
                            .padding(.top, 16)

                            Text(step.title)
                                .font(.title2.bold())
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)

                            Text(step.bodyText)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 28)

                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "lightbulb.fill")
                                    .foregroundStyle(.orange)
                                    .accessibilityHidden(true)
                                Text(step.tipText)
                                    .font(.footnote)
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.leading)
                            }
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color(.secondarySystemBackground))
                            )
                            .padding(.horizontal, 28)

                            Spacer(minLength: 16)
                        }
                    }
                    .tag(step.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            VStack(spacing: 12) {
                Button(action: advanceOrFinish) {
                    Text(currentPage < steps.count - 1 ? "Next" : "Start Tracing")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.accentColor)
                        )
                }
                .accessibilityLabel(currentPage < steps.count - 1 ? "Next onboarding step" : "Start using TraceAR")
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
        .background(Color(.systemBackground).ignoresSafeArea())
    }

    private func advanceOrFinish() {
        HapticsManager.lightTap()
        if currentPage < steps.count - 1 {
            if reduceMotion {
                currentPage += 1
            } else {
                withAnimation(.easeInOut(duration: 0.25)) {
                    currentPage += 1
                }
            }
        } else {
            completeOnboarding()
        }
    }

    private func completeOnboarding() {
        HapticsManager.notifySuccess()
        onFinish()
    }
}
