import AnyLanguageModel
import Foundation
import Testing
@testable import Anvil

struct ToolLanguageModelInvokerTests {
    @MainActor
    @Test
    func respondFallsBackToNonStreamingWhenStreamIsEmpty() async throws {
        let invoker = Self.makeInvoker(model: EmptyStreamLanguageModel())
        let session = invoker.makeSession(for: .metadata, instructions: "instructions")

        let text: String = try await invoker.respond(
            stage: .metadata,
            in: session,
            to: "prompt"
        )

        #expect(text == "fallback response")
    }

    @MainActor
    @Test
    func respondRethrowsStreamErrorsThatAreNotEmptyStream() async {
        let invoker = Self.makeInvoker(model: ThrowingStreamLanguageModel())
        let session = invoker.makeSession(for: .metadata, instructions: "instructions")

        await #expect(throws: FakeInferenceError.self) {
            let _: String = try await invoker.respond(
                stage: .metadata,
                in: session,
                to: "prompt"
            )
        }
    }

    @MainActor
    private static func makeInvoker(model: any LanguageModel) -> ToolLanguageModelInvoker {
        let configuration = ToolGenerationStageConfiguration(
            stage: .metadata,
            languageModel: model,
            generationOptions: GenerationOptions(),
            streaming: true
        )
        return ToolLanguageModelInvoker(
            codingAgent: configuration,
            promptRefinement: configuration,
            metadata: configuration
        )
    }
}

/// Streams zero snapshots (the stream finishes immediately), the way a
/// provider that never emits text deltas behaves; non-streaming works.
private struct EmptyStreamLanguageModel: LanguageModel {
    typealias UnavailableReason = Never

    func respond<Content>(
        within session: LanguageModelSession,
        to prompt: Prompt,
        generating type: Content.Type,
        includeSchemaInPrompt: Bool,
        options: GenerationOptions
    ) async throws -> LanguageModelSession.Response<Content> where Content: Generable {
        guard type == String.self else {
            throw FakeInferenceError.expected
        }
        let text = "fallback response"
        return LanguageModelSession.Response(
            content: text as! Content,
            rawContent: GeneratedContent(text),
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
        LanguageModelSession.ResponseStream(
            stream: AsyncThrowingStream { continuation in
                continuation.finish()
            }
        )
    }
}

/// Streams a real error; the invoker must rethrow it rather than retry.
private struct ThrowingStreamLanguageModel: LanguageModel {
    typealias UnavailableReason = Never

    func respond<Content>(
        within session: LanguageModelSession,
        to prompt: Prompt,
        generating type: Content.Type,
        includeSchemaInPrompt: Bool,
        options: GenerationOptions
    ) async throws -> LanguageModelSession.Response<Content> where Content: Generable {
        throw FakeInferenceError.unexpectedNonStreamingRetry
    }

    func streamResponse<Content>(
        within session: LanguageModelSession,
        to prompt: Prompt,
        generating type: Content.Type,
        includeSchemaInPrompt: Bool,
        options: GenerationOptions
    ) -> sending LanguageModelSession.ResponseStream<Content> where Content: Generable {
        LanguageModelSession.ResponseStream(
            stream: AsyncThrowingStream { continuation in
                continuation.finish(throwing: FakeInferenceError.expected)
            }
        )
    }
}
