import Foundation
import Combine

// MARK: - Session value type

/// The single source of truth for what's happening in a composition session.
/// This is a value type deliberately — mutations are cheap and copying is trivial.
/// One controller owns it; all others observe via published state.
struct CompositionSession {
    /// Raw Latin characters the user has typed since the last commit or cancel.
    var buffer: String = ""

    /// The currently active language profile.
    var profile: LanguageProfile

    /// The ranked candidates from the most recent transliteration lookup.
    var candidates: [TransliterationCandidate] = []

    /// Index into `candidates` that is currently highlighted in the overlay panel.
    var selectionIndex: Int = 0

    /// Whether a network request is currently in flight.
    var isLoading: Bool = false

    /// Whether the last lookup attempt failed (used to show "unavailable" UI).
    var lookupFailed: Bool = false

    var isEmpty: Bool { buffer.isEmpty }

    var selectedCandidate: TransliterationCandidate? {
        guard !candidates.isEmpty, selectionIndex < candidates.count else { return nil }
        return candidates[selectionIndex]
    }

    /// Append a character to the buffer.
    mutating func append(_ character: Character) {
        buffer.append(character)
        // Reset selection when the buffer changes — don't preserve stale index.
        selectionIndex = 0
        lookupFailed = false
    }

    /// Remove the last character (backspace handling).
    mutating func deleteBack() {
        guard !buffer.isEmpty else { return }
        buffer.removeLast()
        selectionIndex = 0
        candidates = []
        lookupFailed = false
    }

    mutating func reset() {
        buffer = ""
        candidates = []
        selectionIndex = 0
        isLoading = false
        lookupFailed = false
    }
}

// MARK: - Controller

/// Orchestrates the composition lifecycle:
///   EventTapManager calls `receive(character:)` / `handleSpecialKey(_:)` on keystrokes.
///   CompositionController debounces, calls TransliterationService, updates session state,
///   and tells CandidateOverlayController to show/hide/reposition.
@MainActor
final class CompositionController: ObservableObject {

    @Published private(set) var session: CompositionSession

    private let service: TransliterationService
    private let textInjector: TextInjector
    private let overlayController: CandidateOverlayController

    /// Debounce window: wait this long after the last keystroke before issuing a network request.
    private let debounceInterval: TimeInterval = 0.13 // 130ms

    /// The in-flight lookup task, cancelled if the buffer changes before it resolves.
    private var lookupTask: Task<Void, Never>?

    init(
        profile: LanguageProfile = .sinhala,
        service: TransliterationService,
        textInjector: TextInjector,
        overlayController: CandidateOverlayController
    ) {
        self.session = CompositionSession(profile: profile)
        self.service = service
        self.textInjector = textInjector
        self.overlayController = overlayController
        // Wire click-to-commit: the panel calls back here when the user taps a row.
        // The weak capture prevents a retain cycle (controller → overlay → closure → controller).
        overlayController.onCandidateSelected = { [weak self] index in
            Task { @MainActor in self?.commitCandidate(at: index) }
        }
    }

    // MARK: - Keystroke handling (called from EventTapManager)

    /// Called by EventTapManager for each printable Latin character captured while armed.
    func receive(character: Character) {
        session.append(character)
        scheduleLookup()
        updateOverlay()
    }

    /// Called by EventTapManager for backspace while composing.
    func handleBackspace() {
        session.deleteBack()
        if session.isEmpty {
            cancelComposition()
        } else {
            scheduleLookup()
            updateOverlay()
        }
    }

    /// Called by EventTapManager for navigation/commit/cancel keys while the panel is visible.
    /// Returns true if the key was consumed (should be swallowed by the tap), false to pass through.
    @discardableResult
    func handleSpecialKey(_ key: CompositionKey) -> Bool {
        guard !session.isEmpty || key == .escape else { return false }

        switch key {
        case .arrowUp:
            guard !session.candidates.isEmpty else { return false }
            session.selectionIndex = max(0, session.selectionIndex - 1)
            overlayController.update(session: session)
            return true

        case .arrowDown:
            guard !session.candidates.isEmpty else { return false }
            session.selectionIndex = min(session.candidates.count - 1, session.selectionIndex + 1)
            overlayController.update(session: session)
            return true

        case .commit:   // Enter — commit highlighted candidate, end composition
            commitSelected()
            return true

        case .space:    // Space — commit top candidate, then let the space through as a word separator
            commitSelected()
            // Don't swallow space itself — we let it pass through to naturally separate words.
            return false

        case .escape:
            cancelComposition()
            return true

        case .numberSelect(let n):
            let idx = n - 1
            if idx >= 0 && idx < session.candidates.count {
                session.selectionIndex = idx
                commitSelected()
            }
            return true
        }
    }

    // MARK: - Commit / cancel

    private func commitSelected() {
        guard let candidate = session.selectedCandidate else {
            cancelComposition()
            return
        }
        // Latin characters are swallowed by the event tap — the text field is clean at the cursor.
        // Injection is a pure insert (deleteCount = 0).
        let latinCount = 0
        lookupTask?.cancel()
        session.reset()
        overlayController.hide()

        // Trailing space so the next word can start immediately after commit.
        let textToInject = candidate.text + " "

        // Small delay so the overlay fade-out finishes before injection fires.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000) // 50 ms
            await textInjector.inject(candidate: textToInject, deletingLatinChars: latinCount)
        }
    }

    /// Commit a specific candidate by index — called from the click handler in the panel.
    func commitCandidate(at index: Int) {
        guard index >= 0, index < session.candidates.count else { return }
        session.selectionIndex = index
        commitSelected()
    }

    func cancelComposition() {
        lookupTask?.cancel()
        session.reset()
        overlayController.hide()
    }

    // MARK: - Debounced lookup

    private func scheduleLookup() {
        lookupTask?.cancel()
        lookupTask = Task { [weak self] in
            // Wait for the debounce window.
            try? await Task.sleep(nanoseconds: UInt64(self?.debounceInterval ?? 0.13 * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }

            let text = await self.session.buffer
            let profile = await self.session.profile
            guard !text.isEmpty else { return }

            await MainActor.run { self.session.isLoading = true }
            self.overlayController.update(session: await self.session)

            let results = await self.service.candidates(for: text, profile: profile)

            guard !Task.isCancelled else { return }

            await MainActor.run {
                self.session.isLoading = false
                
                var candidates = results
                // Always append the raw text as the final candidate option if not already present.
                if !text.isEmpty && !candidates.contains(where: { $0.text.lowercased() == text.lowercased() }) {
                    candidates.append(TransliterationCandidate(text: text, rank: candidates.count))
                }
                
                self.session.candidates = candidates
                self.session.selectionIndex = 0
                self.session.lookupFailed = results.isEmpty
                
                self.updateOverlay()
            }
        }
    }

    // MARK: - Overlay

    private func updateOverlay() {
        if session.isEmpty {
            overlayController.hide()
        } else {
            overlayController.showOrUpdate(session: session)
        }
    }
}

// MARK: - Key enum

/// Keys that CompositionController understands while a session is active.
enum CompositionKey: Equatable {
    case arrowUp
    case arrowDown
    case commit         // Enter/Return
    case space
    case escape
    case numberSelect(Int)  // 1–5 for direct candidate selection
}
