import SwiftUI

/// The SwiftUI view rendered inside the floating candidate overlay panel.
/// Design goals: native-feeling, minimal chrome, clearly readable even over varied backgrounds.
struct CandidatePanelView: View {

    let session: CompositionSession
    /// Called when the user clicks a row. Argument is the candidate index.
    var onSelect: ((Int) -> Void)?
    @State private var isVisible = false

    // MARK: - Body

    var body: some View {
        ZStack {
            // Frosted glass background — looks native and lets the user see the text behind.
            RoundedRectangle(cornerRadius: 12)
                .glassEffect( in: .rect(cornerRadius: 12))
                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 3)

            VStack(alignment: .leading, spacing: 0) {
                headerRow
                Divider().opacity(0.4)
                contentArea
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .frame(minWidth: 200, maxWidth: 320)
        .fixedSize(horizontal: false, vertical: true)
        .padding(1) // 1pt border room for the shadow to show
        .scaleEffect(isVisible ? 1.0 : 0.96)
        .opacity(isVisible ? 1.0 : 0.0)
        .onAppear {
            withAnimation(.spring(response: 0.18, dampingFraction: 0.76)) {
                isVisible = true
            }
        }
    }

    // MARK: - Sub-views

    private var headerRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "character.cursor.ibeam")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            
            // Show the raw English/Latin text in the header
            if !session.buffer.isEmpty {
                Text("› \(session.buffer)")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.accentColor.opacity(0.12))
                    )
            }
            
            // Show a small offline warning icon if API lookup failed
            if session.lookupFailed {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
            }
            
            Spacer()
            
            Text(session.profile.displayName)
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    @ViewBuilder
    private var contentArea: some View {
        if session.isLoading {
            loadingView
        } else if session.candidates.isEmpty {
            emptyView
        } else {
            candidateList
        }
    }

    private var loadingView: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.7)
                .frame(width: 16, height: 16)
            Text("Looking up \"\(session.buffer)\"…")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var unavailableView: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 12))
                .foregroundStyle(.orange)
            Text("Transliteration unavailable")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var emptyView: some View {
        Text("Type to transliterate…")
            .font(.system(size: 12))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
    }

    private var candidateList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(session.candidates.enumerated()), id: \.element.id) { index, candidate in
                CandidateRow(
                    candidate: candidate,
                    rank: index,
                    isSelected: index == session.selectionIndex,
                    onTap: { onSelect?(index) }
                )
                if index < session.candidates.count - 1 {
                    Divider()
                        .padding(.leading, 36)
                        .opacity(0.3)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Candidate row

private struct CandidateRow: View {

    let candidate: TransliterationCandidate
    let rank: Int
    let isSelected: Bool
    var onTap: (() -> Void)? = nil

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            // Rank badge (1-indexed for display)
            Text("\(rank + 1)")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(isSelected ? Color.white.opacity(0.8) : Color.secondary.opacity(0.5))
                .frame(width: 18, height: 18)
                .background(
                    Circle()
                        .fill(isSelected ? Color.accentColor : Color.primary.opacity(0.08))
                )

            // Candidate text — uses a larger font since it's script text, not Latin
            Text(candidate.text)
                .font(.system(size: 18, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.85))

            Spacer()

            // Keyboard hint for selected row, or click hint on hover
            if isSelected {
                keyHint("↵")
            } else if isHovered {
                keyHint("click")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    isSelected
                        ? Color.accentColor.opacity(0.15)
                        : isHovered ? Color.primary.opacity(0.06) : Color.clear
                )
                .padding(.horizontal, 4)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .onTapGesture { onTap?() }
        .animation(.easeInOut(duration: 0.1), value: isSelected)
        .animation(.easeInOut(duration: 0.08), value: isHovered)
    }

    private func keyHint(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.primary.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.primary.opacity(0.15), lineWidth: 0.5)
                    )
            )
    }
}

#if DEBUG
#Preview {
    CandidatePanelView(session: {
        var s = CompositionSession(profile: .sinhala)
        s.buffer = "amma"
        s.candidates = [
            TransliterationCandidate(text: "අම්මා", rank: 0),
            TransliterationCandidate(text: "අමා", rank: 1),
            TransliterationCandidate(text: "ඇම", rank: 2),
        ]
        s.selectionIndex = 0
        return s
    }())
    .frame(width: 300)
    .padding()
}
#endif
