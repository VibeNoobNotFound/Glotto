// GoogleTransliterationProvider.cs
// Port of GoogleTransliterationProvider in TransliterationProvider.swift.
//
// Calls the unofficial but empirically stable Google Input Tools endpoint.
// URL pattern:
//   GET https://inputtools.google.com/request
//       ?text={urlEncodedLatinBuffer}
//       &itc={profile.GoogleInputToolsCode}
//       &num=5&cp=0&cs=1&ie=utf-8&oe=utf-8&app=glotto
//
// Response shape (for a single-word query):
//   ["SUCCESS",[["<echoed-input>",["candidate0","candidate1",...],[],{metadata}]]]
//
// This is an undocumented endpoint — parse loosely and degrade gracefully on any unexpected shape.

using System;
using System.Collections.Generic;
using System.IO;
using System.Net.Http;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using Glotto.WinUI.Core;

namespace Glotto.WinUI.Providers;

public sealed class GoogleTransliterationProvider : ITransliterationProvider
{
    private static readonly HttpClient s_http = new()
    {
        Timeout = TimeSpan.FromSeconds(3)   // short timeout — undocumented backend with no SLA
    };

    public async Task<IReadOnlyList<TransliterationCandidate>> GetCandidatesAsync(
        string text,
        LanguageProfile profile,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrEmpty(text)) return [];

        try
        {
            var url = BuildUrl(text, profile.GoogleInputToolsCode);
            using var response = await s_http.GetAsync(url, cancellationToken);
            response.EnsureSuccessStatusCode();

            await using var stream = await response.Content.ReadAsStreamAsync(cancellationToken);
            return ParseResponse(stream);
        }
        catch (OperationCanceledException)
        {
            throw;  // propagate cancellation — TransliterationService handles it
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"[GoogleTransliterationProvider] Failed: {ex.Message}");
            return [];
        }
    }

    // MARK: - URL construction

    private static string BuildUrl(string text, string itc)
    {
        var encoded = Uri.EscapeDataString(text);
        var encodedItc = Uri.EscapeDataString(itc);
        return $"https://inputtools.google.com/request" +
               $"?text={encoded}" +
               $"&itc={encodedItc}" +
               $"&num=5&cp=0&cs=1&ie=utf-8&oe=utf-8&app=glotto";
    }

    // MARK: - Response decoding

    /// <summary>
    /// Decodes the loosely-typed JSON response.
    /// Structure: [statusString, [[echoedInput, [candidates...], [], {metadata}], ...]]
    /// Parsed defensively — any deviation returns an empty list rather than throwing.
    /// </summary>
    private static IReadOnlyList<TransliterationCandidate> ParseResponse(Stream stream)
    {
        try
        {
            using var doc = JsonDocument.Parse(stream);
            var root = doc.RootElement;

            // Expect: ["SUCCESS", [[...]]]
            if (root.ValueKind != JsonValueKind.Array || root.GetArrayLength() < 2)
                return [];

            if (root[0].GetString() != "SUCCESS")
                return [];

            var segments = root[1];
            if (segments.ValueKind != JsonValueKind.Array || segments.GetArrayLength() == 0)
                return [];

            // Take the first segment — the plan says "at least one element, use the first"
            var firstSegment = segments[0];
            if (firstSegment.ValueKind != JsonValueKind.Array || firstSegment.GetArrayLength() < 2)
                return [];

            var candidatesArray = firstSegment[1];
            if (candidatesArray.ValueKind != JsonValueKind.Array)
                return [];

            var results = new List<TransliterationCandidate>();
            var rank = 0;
            foreach (var element in candidatesArray.EnumerateArray())
            {
                var candidateText = element.GetString();
                if (candidateText is not null)
                    results.Add(new TransliterationCandidate(candidateText, rank++));
            }

            return results;
        }
        catch (JsonException ex)
        {
            System.Diagnostics.Debug.WriteLine($"[GoogleTransliterationProvider] JSON parse error: {ex.Message}");
            return [];
        }
    }
}
