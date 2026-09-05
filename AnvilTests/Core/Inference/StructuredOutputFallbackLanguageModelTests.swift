import AnyLanguageModel
import Foundation
import Testing
@testable import Anvil

@Generable(description: "Test plan for structured output fallback tests.")
struct FallbackTestPlan {
    @Guide(description: "A display name.")
    let displayName: String

    @Guide(description: "A list of tags.")
    let tags: [String]
}

private final class ScriptedBaseModelBox: @unchecked Sendable {
    var strictRespondCalls = 0
    var strictStreamCalls = 0
    var plainRespondCalls = 0
    var plainReplies: [String] = []
    var strictError: (any Error)?
    var strictSuccessJSON = #"{"displayName":"Strict","tags":["native"]}"#
    var emptyStream = false
}

private struct ScriptedBaseLanguageModel: LanguageModel {
    typealias UnavailableReason = Never

    let box: ScriptedBaseModelBox

    func respond<Content>(
        within session: LanguageModelSession,
        to prompt: Prompt,
        generating type: Content.Type,
        includeSchemaInPrompt: Bool,
        options: GenerationOptions
    ) async throws -> LanguageModelSession.Response<Content> where Content: Generable {
        if Content.self == String.self {
            box.plainRespondCalls += 1
            let reply = box.plainReplies.isEmpty ? "" : box.plainReplies.removeFirst()
            return LanguageModelSession.Response(
                content: reply as! Content,
                rawContent: GeneratedContent(reply),
                transcriptEntries: []
            )
        }
        box.strictRespondCalls += 1
        if let error = box.strictError {
            throw error
        }
        let raw = try GeneratedContent(json: box.strictSuccessJSON)
        return LanguageModelSession.Response(
            content: try Content(raw),
            rawContent: raw,
            transcriptEntries: []
        )
    }

    func streamResponse<Content>(
        within session: LanguageModelSession,
        to prompt: Prompt,
        generating type: Content.Type,
        includeSchemaInPrompt: Bool,
        options: GenerationOptions
    ) -> sending LanguageModelSession.ResponseStream<Content> where Content: Generable {
        let box = box
        return LanguageModelSession.ResponseStream(
            stream: AsyncThrowingStream { continuation in
                let task = Task {
                    if Content.self == String.self {
                        continuation.finish()
                        return
                    }
                    box.strictStreamCalls += 1
                    if let error = box.strictError {
                        continuation.finish(throwing: error)
                        return
                    }
                    if box.emptyStream {
                        continuation.finish()
                        return
                    }
                    do {
                        let raw = try GeneratedContent(json: box.strictSuccessJSON)
                        let content = try Content(raw)
                        continuation.yield(
                            .init(
                                content: content.asPartiallyGenerated(),
                                rawContent: raw
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
}

private enum FakeProviderError: Error {
    case noResponseGenerated
    case unauthorized
}

private struct FakeHTTPError: Error, CustomStringConvertible {
    let description: String
}

struct StructuredOutputFallbackLanguageModelTests {
    private func makeSession(
        _ model: StructuredOutputFallbackLanguageModel
    ) -> LanguageModelSession {
        LanguageModelSession(model: model, instructions: "Test instructions.")
    }

    @Test
    func passesThroughWhenStrictStructuredOutputSucceeds() async throws {
        let box = ScriptedBaseModelBox()
        let model = StructuredOutputFallbackLanguageModel(base: ScriptedBaseLanguageModel(box: box))
        let session = makeSession(model)

        let response = try await model.respond(
            within: session,
            to: Prompt("Name this app."),
            generating: FallbackTestPlan.self,
            includeSchemaInPrompt: true,
            options: GenerationOptions()
        )

        #expect(response.content.displayName == "Strict")
        #expect(box.strictRespondCalls == 1)
        #expect(box.plainRespondCalls == 0)
    }

    @Test
    func fallsBackToPromptedJSONWhenProviderReturnsNothing() async throws {
        let box = ScriptedBaseModelBox()
        box.strictError = FakeProviderError.noResponseGenerated
        box.plainReplies = [#"{"displayName":"Paint Studio","tags":["art","fun"]}"#]
        let model = StructuredOutputFallbackLanguageModel(base: ScriptedBaseLanguageModel(box: box))
        let session = makeSession(model)

        let response = try await model.respond(
            within: session,
            to: Prompt("Name this app."),
            generating: FallbackTestPlan.self,
            includeSchemaInPrompt: true,
            options: GenerationOptions()
        )

        #expect(response.content.displayName == "Paint Studio")
        #expect(response.content.tags == ["art", "fun"])
        #expect(box.strictRespondCalls == 1)
        #expect(box.plainRespondCalls == 1)

        // The verdict is cached: the next structured request skips the
        // doomed strict attempt entirely.
        box.plainReplies = [#"{"displayName":"Second","tags":[]}"#]
        let second = try await model.respond(
            within: session,
            to: Prompt("Name this app."),
            generating: FallbackTestPlan.self,
            includeSchemaInPrompt: true,
            options: GenerationOptions()
        )
        #expect(second.content.displayName == "Second")
        #expect(box.strictRespondCalls == 1)
        #expect(box.plainRespondCalls == 2)
    }

    @Test
    func fallsBackWhenProviderRejectsStructuredParameters() async throws {
        let box = ScriptedBaseModelBox()
        box.strictError = FakeHTTPError(
            description: "HTTP error (Status 400): Invalid parameter: response_format"
        )
        box.plainReplies = [#"{"displayName":"Rejected","tags":[]}"#]
        let model = StructuredOutputFallbackLanguageModel(base: ScriptedBaseLanguageModel(box: box))
        let session = makeSession(model)

        let response = try await model.respond(
            within: session,
            to: Prompt("Name this app."),
            generating: FallbackTestPlan.self,
            includeSchemaInPrompt: true,
            options: GenerationOptions()
        )

        #expect(response.content.displayName == "Rejected")
        #expect(box.plainRespondCalls == 1)
    }

    @Test
    func rethrowsErrorsUnrelatedToStructuredOutput() async throws {
        let box = ScriptedBaseModelBox()
        box.strictError = FakeProviderError.unauthorized
        let model = StructuredOutputFallbackLanguageModel(base: ScriptedBaseLanguageModel(box: box))
        let session = makeSession(model)

        await #expect(throws: FakeProviderError.self) {
            _ = try await model.respond(
                within: session,
                to: Prompt("Name this app."),
                generating: FallbackTestPlan.self,
                includeSchemaInPrompt: true,
                options: GenerationOptions()
            )
        }
        #expect(box.plainRespondCalls == 0)
    }

    @Test
    func extractsJSONFromMarkdownFences() async throws {
        let box = ScriptedBaseModelBox()
        box.strictError = FakeProviderError.noResponseGenerated
        box.plainReplies = ["```json\n{\"displayName\":\"Fenced\",\"tags\":[\"x\"]}\n```"]
        let model = StructuredOutputFallbackLanguageModel(base: ScriptedBaseLanguageModel(box: box))
        let session = makeSession(model)

        let response = try await model.respond(
            within: session,
            to: Prompt("Name this app."),
            generating: FallbackTestPlan.self,
            includeSchemaInPrompt: true,
            options: GenerationOptions()
        )

        #expect(response.content.displayName == "Fenced")
        #expect(box.plainRespondCalls == 1)
    }

    @Test
    func repairsInvalidJSONOnceBeforeThrowing() async throws {
        let box = ScriptedBaseModelBox()
        box.strictError = FakeProviderError.noResponseGenerated
        box.plainReplies = [
            "Sure! Here is the JSON you asked for:",
            #"{"displayName":"Repaired","tags":[]}"#,
        ]
        let model = StructuredOutputFallbackLanguageModel(base: ScriptedBaseLanguageModel(box: box))
        let session = makeSession(model)

        let response = try await model.respond(
            within: session,
            to: Prompt("Name this app."),
            generating: FallbackTestPlan.self,
            includeSchemaInPrompt: true,
            options: GenerationOptions()
        )

        #expect(response.content.displayName == "Repaired")
        #expect(box.plainRespondCalls == 2)
    }

    @Test
    func throwsAfterTwoUndecodableReplies() async throws {
        let box = ScriptedBaseModelBox()
        box.strictError = FakeProviderError.noResponseGenerated
        box.plainReplies = ["not json at all", "still not json"]
        let model = StructuredOutputFallbackLanguageModel(base: ScriptedBaseLanguageModel(box: box))
        let session = makeSession(model)

        await #expect(throws: StructuredOutputFallbackError.self) {
            _ = try await model.respond(
                within: session,
                to: Prompt("Name this app."),
                generating: FallbackTestPlan.self,
                includeSchemaInPrompt: true,
                options: GenerationOptions()
            )
        }
        #expect(box.plainRespondCalls == 2)
    }

    @Test
    func recoversFromEmptyStructuredStream() async throws {
        let box = ScriptedBaseModelBox()
        box.emptyStream = true
        box.plainReplies = [#"{"displayName":"Streamed","tags":["s"]}"#]
        let model = StructuredOutputFallbackLanguageModel(base: ScriptedBaseLanguageModel(box: box))
        let session = makeSession(model)

        var snapshots: [FallbackTestPlan.PartiallyGenerated] = []
        let stream = model.streamResponse(
            within: session,
            to: Prompt("Name this app."),
            generating: FallbackTestPlan.self,
            includeSchemaInPrompt: true,
            options: GenerationOptions()
        )
        for try await snapshot in stream {
            snapshots.append(snapshot.content)
        }

        #expect(snapshots.count == 1)
        #expect(snapshots.first?.displayName == "Streamed")
        #expect(box.strictStreamCalls == 1)
        #expect(box.plainRespondCalls == 1)
    }

    @Test
    func passesPlainStringRequestsThrough() async throws {
        let box = ScriptedBaseModelBox()
        box.plainReplies = ["just text"]
        let model = StructuredOutputFallbackLanguageModel(base: ScriptedBaseLanguageModel(box: box))
        let session = makeSession(model)

        let response = try await model.respond(
            within: session,
            to: Prompt("Say something."),
            generating: String.self,
            includeSchemaInPrompt: true,
            options: GenerationOptions()
        )

        #expect(response.content == "just text")
        #expect(box.strictRespondCalls == 0)
        #expect(box.plainRespondCalls == 1)
    }
}
