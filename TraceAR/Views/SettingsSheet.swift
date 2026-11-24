import SwiftUI

struct SettingsSheet: View {
    @Binding var keepScreenAwake: Bool
    let onReplayOnboarding: () -> Void
    let onResetARSession: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(isOn: $keepScreenAwake) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Keep Screen Awake")
                                Text("Prevents your iPhone from dimming while tracing in AR")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "sun.max.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                    .frame(minHeight: 44)
                } header: {
                    Text("Tracing Stability")
                }

                Section {
                    Button {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            onReplayOnboarding()
                        }
                    } label: {
                        Label("Replay 3-Step Setup Guide", systemImage: "book.fill")
                            .frame(minHeight: 44)
                    }

                    Button(role: .destructive) {
                        onResetARSession()
                        dismiss()
                    } label: {
                        Label("Reset AR Surface & Filters", systemImage: "arrow.counterclockwise")
                            .frame(minHeight: 44)
                    }
                } header: {
                    Text("Help & Controls")
                }

                Section {
                    Label("100% Offline — Zero Network Calls", systemImage: "wifi.slash")
                    Label("No Ads, Subscriptions, or Tracking", systemImage: "hand.raised.fill")
                    Label("Camera Video Never Leaves Device", systemImage: "lock.shield.fill")
                } header: {
                    Text("Privacy")
                } footer: {
                    Text("TraceAR processes camera frames and Core Image edge filters locally on your iPhone.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .frame(minWidth: 44, minHeight: 44)
                }
            }
        }
    }
}
