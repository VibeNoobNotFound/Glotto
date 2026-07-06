import SwiftUI

/// First-run onboarding shown when Accessibility permission is missing.
/// Guides the user through granting Accessibility permission, and polls
/// for grants so the window closes automatically once authorized.
struct PermissionOnboardingView: View {

    @EnvironmentObject private var permissionManager: PermissionManager
    var onAllGranted: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            // Hero header
            header

            Divider()

            // Permission card & help tip
            VStack(spacing: 20) {
                PermissionCard(
                    icon: "hand.tap",
                    iconColor: .blue,
                    title: "Accessibility Permission",
                    description: "Accessibility is required for Glotto to query cursor coordinates, detect active input fields, and capture/inject transliterated text.",
                    granted: permissionManager.hasAccessibility,
                    buttonLabel: "Open Accessibility Settings",
                    onButton: {
                        permissionManager.requestAccessibilityIfNeeded()
                        permissionManager.openAccessibilitySettings()
                    }
                )

                // Developer / Re-authorization Tip Box
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Already Checked in Settings?")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.primary)
                        Text("macOS invalidates permissions when local app binaries are rebuilt. If Glotto is already listed, toggle the checkbox off and back on in System Settings to re-authorize it.")
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

            Text("Glotto needs Accessibility permission to capture Latin typing\nand replace it inline with your target script.")
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
                Label("Waiting for Accessibility permission…", systemImage: "clock")
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
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(granted ? Color.green.opacity(0.4) : Color.primary.opacity(0.08), lineWidth: 1)
        )
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
