import SwiftUI

/// First-run onboarding shown when one or more required permissions are missing.
/// Guides the user through granting Accessibility and Input Monitoring, then polls
/// so the window closes automatically once both are authorized.
struct PermissionOnboardingView: View {

    @EnvironmentObject private var permissionManager: PermissionManager
    var onAllGranted: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            // Hero header
            header

            Divider()

            // Permission cards
            VStack(spacing: 16) {
                PermissionCard(
                    icon: "hand.tap",
                    iconColor: .blue,
                    title: "Accessibility",
                    description: "Required for Glotto to query cursor coordinates, detect active input fields, and inject transliterated text.",
                    granted: permissionManager.hasAccessibility,
                    buttonLabel: "Open Accessibility Settings",
                    onButton: {
                        permissionManager.requestAccessibilityIfNeeded()
                        permissionManager.openAccessibilitySettings()
                    }
                )

                PermissionCard(
                    icon: "keyboard.fill",
                    iconColor: .purple,
                    title: "Input Monitoring",
                    description: "Required for Glotto's global key-intercept tap. Without this, arming fails silently — macOS gates session-level CGEventTap behind Input Monitoring separately from Accessibility.",
                    granted: permissionManager.hasInputMonitoring,
                    buttonLabel: "Open Input Monitoring Settings",
                    onButton: {
                        permissionManager.requestInputMonitoringIfNeeded()
                        permissionManager.openInputMonitoringSettings()
                    }
                )

                // Developer / Re-authorization Tip Box
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Already checked in Settings?")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.primary)
                        Text("macOS invalidates permissions when local app binaries are rebuilt. If Glotto is already listed, remove Glotto and add it and enable it and back on in System Settings to re-authorize it.")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineSpacing(2)
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(0.04))
                )
            }
            .padding(24)

            Divider()

            // Status footer
            footer
        }
        .background(.ultraThinMaterial) 
        .frame(width: 480)
        .onAppear {
            permissionManager.refresh()
            permissionManager.startPolling { onAllGranted() }
        }
        .onDisappear {
            permissionManager.stopPolling()
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "character.bubble.fill")
                .font(.system(size: 48))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .symbolRenderingMode(.hierarchical)

            Text("Welcome to Glotto")
                .font(.system(size: 22, weight: .bold, design: .rounded))

            Text("Glotto needs Accessibility and Input Monitoring\nto capture Latin typing and inject your target script.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(28)
    }

    private var footer: some View {
        HStack {
            if permissionManager.allGranted {
                Label("All set! You can close this window.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.subheadline.weight(.medium))
            } else {
                Label(
                    permissionGrantedSummary,
                    systemImage: "clock"
                )
                .foregroundStyle(.secondary)
                .font(.subheadline)
            }
            Spacer()
            if permissionManager.allGranted {
                Button("Get Started") { onAllGranted() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private var permissionGrantedSummary: String {
        switch (permissionManager.hasAccessibility, permissionManager.hasInputMonitoring) {
        case (false, false): return "Waiting for Accessibility and Input Monitoring…"
        case (true, false):  return "Waiting for Input Monitoring…"
        case (false, true):  return "Waiting for Accessibility…"
        case (true, true):   return "All permissions granted."
        }
    }
}

// MARK: - Permission card

private struct PermissionCard: View {

    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    let granted: Bool
    let buttonLabel: String
    let onButton: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(iconColor.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(iconColor)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(title).font(.headline)
                    Spacer()
                    statusBadge
                }
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !granted {
                    Button(buttonLabel, action: onButton)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .padding(.top, 2)
                }
            }
        }
        .padding(16)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(granted ? Color.green.opacity(0.4) : Color.primary.opacity(0.08), lineWidth: 1)
        ).glassEffect(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var statusBadge: some View {
        Group {
            if granted {
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption.weight(.medium))
            } else {
                Label("Required", systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption.weight(.medium))
            }
        }
    }
}

#if DEBUG
#Preview {
    PermissionOnboardingView()
        .environmentObject(PermissionManager())
}
#endif
