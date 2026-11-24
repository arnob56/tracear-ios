import SwiftUI
import UIKit

struct ContentView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @AppStorage("keepScreenAwake") private var keepScreenAwake: Bool = true

    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var arViewModel = ARSessionViewModel()
    @StateObject private var sketchViewModel = SketchCanvasViewModel()

    @State private var selectedMode: AppMode = .arTrace
    @State private var isShowingOnboarding: Bool = false
    @State private var isShowingSettings: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                switch selectedMode {
                case .arTrace:
                    ARTraceScreen(
                        viewModel: arViewModel,
                        keepScreenAwake: $keepScreenAwake,
                        onSwitchToSketchPad: { switchMode(to: .sketchPad) },
                        onOpenSettingsSheet: { isShowingSettings = true }
                    )
                case .sketchPad:
                    SketchPadScreen(
                        sketchVM: sketchViewModel,
                        referenceImage: arViewModel.referenceImage,
                        onOpenSettings: { isShowingSettings = true }
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            modeSwitcherBar
        }
        .onAppear {
            arViewModel.onMemoryWarningCleanup = { [weak sketchViewModel] in
                sketchViewModel?.handleMemoryWarning()
            }
            if !hasCompletedOnboarding {
                isShowingOnboarding = true
            } else {
                arViewModel.setARModeActive(selectedMode == .arTrace, keepScreenAwake: keepScreenAwake)
            }
        }
        .onChange(of: selectedMode) { newMode in
            arViewModel.setARModeActive(newMode == .arTrace, keepScreenAwake: keepScreenAwake)
        }
        .onChange(of: keepScreenAwake) { newValue in
            arViewModel.updateIdleTimer(
                keepAwake: newValue,
                active: selectedMode == .arTrace && scenePhase == .active
            )
        }
        .onChange(of: scenePhase) { newPhase in
            arViewModel.handleScenePhaseChange(
                newPhase,
                isCurrentModeAR: selectedMode == .arTrace && !isShowingOnboarding,
                keepScreenAwake: keepScreenAwake
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            arViewModel.handleMemoryWarning()
        }
        .fullScreenCover(isPresented: $isShowingOnboarding) {
            OnboardingView {
                hasCompletedOnboarding = true
                isShowingOnboarding = false
                arViewModel.setARModeActive(selectedMode == .arTrace, keepScreenAwake: keepScreenAwake)
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsSheet(
                keepScreenAwake: $keepScreenAwake,
                onReplayOnboarding: {
                    arViewModel.setARModeActive(false, keepScreenAwake: false)
                    isShowingOnboarding = true
                },
                onResetARSession: {
                    arViewModel.resetFilters()
                    arViewModel.retrySurfaceScan()
                }
            )
        }
    }

    private var modeSwitcherBar: some View {
        HStack(spacing: 8) {
            ForEach(AppMode.allCases) { mode in
                let isSelected = (selectedMode == mode)
                Button {
                    switchMode(to: mode)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: mode.systemImage)
                            .font(.subheadline.weight(.semibold))
                        Text(mode.rawValue)
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(isSelected ? Color.accentColor : Color.clear)
                    )
                    .foregroundStyle(isSelected ? .white : .primary)
                    .contentShape(Rectangle())
                }
                .accessibilityLabel(mode.rawValue)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 6)
        .background(
            Color(.systemBackground)
                .overlay(alignment: .top) {
                    Divider()
                }
        )
    }

    private func switchMode(to mode: AppMode) {
        guard selectedMode != mode else { return }
        HapticsManager.lightTap()
        selectedMode = mode
    }
}
