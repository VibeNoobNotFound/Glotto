import Foundation

// MARK: - Protocol

/// Everything that can generate transliteration candidates must conform to this.
/// In Phase 1, only GoogleTransliterationProvider conforms.
/// In Phase 2, an offline/rule-based engine will be appended to the provider list in
/// TransliterationService — nothing else changes.
protocol TransliterationProvider: Sendable {
    /// Fetch ranked candidates for a single word-in-progress.
    /// `text` is the raw Latin buffer being composed — not yet committed to the target app.
    /// Candidates are ordered best-first (rank 0 = most likely).
    func candidates(for text: String, profile: LanguageProfile) async throws -> [TransliterationCandidate]
}

// MARK: - Model

struct TransliterationCandidate: Identifiable, Equatable, Sendable {
    /// Using the text as the ID is safe here — candidates for a given buffer are always unique strings.
    var id: String { text }
    let text: String
    let rank: Int   // 0 = best, ascending
}

// MARK: - Error

enum TransliterationError: Error {
    case network(underlying: Error)
    case decoding
    case emptyResponse
    case cancelled
}

// MARK: - Google Input Tools provider

/// Calls the unofficial but empirically stable Google Input Tools endpoint.
/// URL pattern:
///   GET https://inputtools.google.com/request
///       ?text=<latin>&itc=<profile.googleInputToolsCode>&num=5&cp=0&cs=1&ie=utf-8&oe=utf-8&app=glotto
///
/// Response shape (for a single-word query):
///   ["SUCCESS", [["<echoed-input>", ["candidate0", "candidate1", ...], [], {metadata}]]]
///
/// This is an undocumented endpoint — parse loosely and degrade gracefully on any unexpected shape.
final class GoogleTransliterationProvider: TransliterationProvider, @unchecked Sendable {

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func candidates(for text: String, profile: LanguageProfile) async throws -> [TransliterationCandidate] {
        guard !text.isEmpty else { return [] }

        let url = try makeURL(text: text, itc: profile.googleInputToolsCode)
        var request = URLRequest(url: url, timeoutInterval: 3.0)   // short timeout — this is best-effort
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw TransliterationError.cancelled
        } catch {
            throw TransliterationError.network(underlying: error)
        }

        // Expect HTTP 200; anything else is treated as an API failure, not a crash.
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw TransliterationError.decoding
        }

        return try decode(data)
    }

    // MARK: - URL construction

    private func makeURL(text: String, itc: String) throws -> URL {
        // Percent-encode text explicitly rather than relying on URLComponents
        // auto-encoding, which can be inconsistent for unusual Unicode input.
        guard let encodedText = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let encodedITC  = itc.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        else {
            throw TransliterationError.decoding
        }

        let urlString = "https://inputtools.google.com/request"
            + "?text=\(encodedText)"
            + "&itc=\(encodedITC)"
            + "&num=5"
            + "&cp=0"
            + "&cs=1"
            + "&ie=utf-8"
            + "&oe=utf-8"
            + "&app=glotto"

        guard let url = URL(string: urlString) else {
            throw TransliterationError.decoding
        }
        return url
    }

    // MARK: - Response decoding

    /// Decodes the loosely-typed JSON response.
    /// Structure: [statusString, [[echoedInput, [candidates...], [], {metadata}], ...]]
    private func decode(_ data: Data) throws -> [TransliterationCandidate] {
        // Decode as a raw JSON array since the response is heterogeneous (mixed string + array).
        guard let topLevel = try? JSONSerialization.jsonObject(with: data) as? [Any],
              topLevel.count >= 2,
              let status = topLevel[0] as? String,
              status == "SUCCESS",
              let segments = topLevel[1] as? [[Any]],
              let firstSegment = segments.first,
              firstSegment.count >= 2,
              let candidateStrings = firstSegment[1] as? [String]
        else {
            // Any deviation from expected shape is treated as a decoding failure,
            // which the service layer maps to an empty result (graceful degradation).
            throw TransliterationError.decoding
        }

        guard !candidateStrings.isEmpty else {
            throw TransliterationError.emptyResponse
        }

        return candidateStrings.enumerated().map { index, text in
            TransliterationCandidate(text: text, rank: index)
        }
    }
}
