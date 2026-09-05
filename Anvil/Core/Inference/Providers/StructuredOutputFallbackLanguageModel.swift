import AnyLanguageModel
import Foundation

/// Wraps a remote language model whose gateway or model may not implement
/// strict json_schema structured output (AnyLanguageModel always requests it
/// for non-String Generable types). The first structured request tries the
/// native strict path; when the provider signals that structured output is
/// unsupported (an empty response, or an HTTP 4xx rejecting the
/// response_format / text.format parameter), the request retries as plain
/// text with the schema embedded in the prompt, and the reply is decoded
/// locally via GeneratedContent's lenient JSON parser. The verdict is cached
/// for the lifetime of the wrapper so later structured requests skip the
/// doomed strict attempt.
nonisolated struct StructuredOutputFallbackLanguageModel: LanguageModel {
    typealias UnavailableReason = Never

    let base: any LanguageModel

    private let verdict = StructuredOutputCapabilityVerdict()

    init(base: any LanguageModel) {
        self.base = base
    }

    func respond<Content>(
        within session: LanguageModelSession,
        to prompt: Prompt,
        generating type: Content.Type,
        includeSchemaInPrompt: Bool,
        options: GenerationOptions
    ) async throws -> LanguageModelSession.Response<Content> where Content: Generable {
        if Content.self == String.self {
            return try await base.respond(
                within: session,
                to: prompt,
                generating: type,
                includeSchemaInPrompt: includeSchemaInPrompt,
                options: options
            )
        }
        if verdict.requiresPromptedJSON {
            return try await respondWithPromptedJSON(
                within: session,
                to: prompt,
                generating: type,
                options: options
            )
        }
        do {
            return try await base.respond(
                within: session,
                to: prompt,
                generating: type,
                includeSchemaInPrompt: includeSchemaInPrompt,
                options: options
            )
        } catch {
            guard Self.signalsUnsupportedStructuredOutput(error) else { throw error }
            verdict.requiresPromptedJSON = true
            return try await respondWithPromptedJSON(
                within: session,
                to: prompt,
                generating: type,
                options: options
            )
        }
    }

    func streamResponse<Content>(
        within session: LanguageModelSession,
        to prompt: Prompt,
        generating type: Content.Type,
        includeSchemaInPrompt: Bool,
        options: GenerationOptions
    ) -> sending LanguageModelSession.ResponseStream<Content> where Content: Generable {
        if Content.self == String.self {
            return base.streamResponse(
                within: session,
                to: prompt,
                generating: type,
                includeSchemaInPrompt: includeSchemaInPrompt,
                options: options
            )
        }
        if verdict.requiresPromptedJSON {
            return LanguageModelSession.ResponseStream(
                stream: AsyncThrowingStream { continuation in
                    let task = Task {
                        do {
                            let response = try await respondWithPromptedJSON(
                                within: session,
                                to: prompt,
                                generating: Content.self,
                                options: options
                            )
                            continuation.yield(
                                .init(
                                    content: response.content.asPartiallyGenerated(),
                                    rawContent: response.rawContent
                                )
                            )
                            continuation.finish()
                        } catch {
                            continuation.finish(throwing: error)
                        }
                    }
                    continuation.onTermination = { _ in task.cancel() }
                }
            )
        }
        let upstream = base.streamResponse(
            within: session,
            to: prompt,
            generating: type,
            includeSchemaInPrompt: includeSchemaInPrompt,
            options: options
        )
        return LanguageModelSession.ResponseStream(
            stream: AsyncThrowingStream { continuation in
                let task = Task {
                    var sawSnapshot = false
                    do {
                        for try await snapshot in upstream {
                            sawSnapshot = true
                            continuation.yield(snapshot)
                        }
                    } catch {
                        guard !sawSnapshot, Self.signalsUnsupportedStructuredOutput(error) else {
                            continuation.finish(throwing: error)
                            return
                        }
                        verdict.requiresPromptedJSON = true
                    }
                    if !sawSnapshot {
                        // The strict structured stream completed empty or
                        // failed before producing anything: fall back to
                        // prompt-instructed JSON and yield a single snapshot.
                        verdict.requiresPromptedJSON = true
                        do {
                            let response = try await respondWithPromptedJSON(
                                within: session,
                                to: prompt,
                                generating: Content.self,
                                options: options
                            )
                            continuation.yield(
                                .init(
                                    content: response.content.asPartiallyGenerated(),
                                    rawContent: response.rawContent
                                )
                            )
                            continuation.finish()
                        } catch {
                            continuation.finish(throwing: error)
                        }
                        return
                    }
                    continuation.finish()
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        )
    }

    // MARK: - Prompt-instructed JSON fallback

    private func respondWithPromptedJSON<Content>(
        within session: LanguageModelSession,
        to prompt: Prompt,
        generating type: Content.Type,
        options: GenerationOptions
    ) async throws -> LanguageModelSession.Response<Content> where Content: Generable {
        let schemaDescription = Self.schemaDescription(for: Content.self)
        var instruction = """
            \(prompt.description)

            Respond with ONLY a JSON object matching the JSON schema below. \
            No markdown fences, no explanation, no text before or after the JSON.

            JSON schema:
            \(schemaDescription)
            """
        var lastFailure = "the reply contained no decodable JSON"
        for attempt in 0 ..< 2 {
            if attempt > 0 {
                instruction = """
                    \(prompt.description)

                    Your previous reply was not valid JSON matching the schema (\(lastFailure)). \
                    Respond with ONLY a corrected JSON object matching the JSON schema below. \
                    No markdown fences, no explanation, no text before or after the JSON.

                    JSON schema:
                    \(schemaDescription)
                    """
            }
            let reply = try await base.respond(
                within: session,
                to: Prompt(instruction),
                generating: String.self,
                includeSchemaInPrompt: false,
                options: options
            ).content
            if let decoded = Self.decodeGeneratedContent(Content.self, from: reply) {
                return LanguageModelSession.Response(
                    content: decoded.content,
                    rawContent: decoded.rawContent,
                    transcriptEntries: []
                )
            }
            lastFailure = "could not parse \(Self.compact(reply, limit: 160))"
        }
        throw StructuredOutputFallbackError.invalidJSON(detail: lastFailure)
    }

    // MARK: - Decoding

    static func decodeGeneratedContent<Content: Generable>(
        _ type: Content.Type,
        from text: String
    ) -> (content: Content, rawContent: GeneratedContent)? {
        for candidate in jsonCandidates(from: text) {
            guard let raw = try? GeneratedContent(json: candidate),
                  let content = try? Content(raw)
            else { continue }
            return (content, raw)
        }
        return nil
    }

    static func jsonCandidates(from text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var candidates: [String] = []
        if !trimmed.isEmpty {
            candidates.append(trimmed)
        }
        var unfenced = trimmed
        if unfenced.hasPrefix("```") {
            var lines = unfenced.components(separatedBy: .newlines)
            lines.removeFirst()
            if let last = lines.last,
               last.trimmingCharacters(in: .whitespaces).hasPrefix("```")
            {
                lines.removeLast()
            }
            unfenced = lines.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !unfenced.isEmpty {
                candidates.append(unfenced)
            }
        }
        for source in [trimmed, unfenced] {
            guard let start = source.firstIndex(of: "{"),
                  let end = source.lastIndex(of: "}"),
                  start < end
            else { continue }
            candidates.append(String(source[start ... end]))
        }
        return candidates
    }

    static func schemaDescription<Content: Generable>(for type: Content.Type) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(Content.generationSchema),
           let string = String(data: data, encoding: .utf8)
        {
            return string
        }
        return Content.generationSchema.debugDescription
    }

    // MARK: - Unsupported-signal detection

    static func signalsUnsupportedStructuredOutput(_ error: Error) -> Bool {
        let text = (String(describing: error) + " " + error.localizedDescription).lowercased()
        // AnyLanguageModel throws its internal noResponseGenerated when a
        // provider answers a structured request with nothing at all.
        if text.contains("noresponsegenerated") {
            return true
        }
        // Gateways that reject the structured-output parameters fail the
        // request with a 4xx naming the offending parameter.
        guard text.contains("status 4") else { return false }
        return text.contains("response_format")
            || text.contains("text.format")
            || text.contains("json_schema")
            || text.contains("output_config")
            || text.contains("structured output")
    }

    private static func compact(_ text: String, limit: Int) -> String {
        let flattened = text.replacingOccurrences(of: "\n", with: " ")
        guard flattened.count > limit else { return flattened }
        return String(flattened.prefix(limit)) + "..."
    }
}

enum StructuredOutputFallbackError: LocalizedError {
    case invalidJSON(detail: String)

    var errorDescription: String? {
        switch self {
        case .invalidJSON(let detail):
            "The model did not return valid JSON matching the schema (\(detail))."
        }
    }
}

/// Session-lifetime record of whether the wrapped provider needs the
/// prompt-instructed JSON path for structured requests.
private final class StructuredOutputCapabilityVerdict: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var requiresPromptedJSON: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
        set {
            lock.lock()
            value = newValue
            lock.unlock()
        }
    }
}
