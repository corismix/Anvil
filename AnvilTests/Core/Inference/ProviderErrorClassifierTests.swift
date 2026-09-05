import Foundation
import Testing
@testable import Anvil

private enum FakeProviderHTTPError: Error {
    case httpError(statusCode: Int, detail: String)
}

private enum FakeUnrelatedError: Error {
    case broken
}

struct ProviderErrorClassifierTests {
    private var matchingType: String { String(reflecting: FakeProviderHTTPError.self) }

    private func httpError(_ statusCode: Int) -> FakeProviderHTTPError {
        .httpError(statusCode: statusCode, detail: "detail")
    }

    @Test
    func extractsStatusCodeFromHTTPError() {
        #expect(
            ProviderErrorClassifier.httpStatusCode(
                from: httpError(500),
                matchingType: matchingType
            ) == 500
        )
    }

    @Test
    func extractsStatusCodeThroughUnderlyingErrorWrapping() {
        let wrapped = NSError(
            domain: "TestDomain",
            code: 1,
            userInfo: [NSUnderlyingErrorKey: httpError(429)]
        )
        #expect(
            ProviderErrorClassifier.httpStatusCode(
                from: wrapped,
                matchingType: matchingType
            ) == 429
        )
    }

    @Test
    func ignoresUnrelatedErrorsAndMismatchedTypeNames() {
        #expect(ProviderErrorClassifier.httpStatusCode(from: FakeUnrelatedError.broken) == nil)
        // Same shape, but not the AnyLanguageModel type: the default matcher
        // must not classify it.
        #expect(ProviderErrorClassifier.httpStatusCode(from: httpError(500)) == nil)
    }

    @Test
    func unauthorizedMessageAsksForSignIn() {
        for statusCode in [401, 403] {
            let message = ProviderErrorClassifier.userFacingMessage(
                for: httpError(statusCode),
                providerName: "OpenAI Codex (ChatGPT)",
                matchingType: matchingType
            )
            #expect(message?.contains("OpenAI Codex (ChatGPT)") == true)
            #expect(message?.contains("HTTP \(statusCode)") == true)
            #expect(message?.contains("sign in again") == true)
        }
    }

    @Test
    func rateLimitMessageNamesTheProvider() {
        let message = ProviderErrorClassifier.userFacingMessage(
            for: httpError(429),
            providerName: "Anthropic",
            matchingType: matchingType
        )
        #expect(message?.contains("Anthropic") == true)
        #expect(message?.contains("rate limited") == true)
    }

    @Test
    func serverErrorMessageBlamesTheProviderNotThePrompt() {
        for statusCode in [500, 502, 503] {
            let message = ProviderErrorClassifier.userFacingMessage(
                for: httpError(statusCode),
                providerName: "OpenAI",
                matchingType: matchingType
            )
            #expect(message?.contains("OpenAI") == true)
            #expect(message?.contains("is erroring") == true)
            #expect(message?.contains("HTTP \(statusCode)") == true)
        }
    }

    @Test
    func otherStatusesGetAGenericMessageAndUnknownProviderIsLabeled() {
        let message = ProviderErrorClassifier.userFacingMessage(
            for: httpError(400),
            providerName: nil,
            matchingType: matchingType
        )
        #expect(message?.contains("The model provider") == true)
        #expect(message?.contains("HTTP 400") == true)

        let emptyName = ProviderErrorClassifier.userFacingMessage(
            for: httpError(400),
            providerName: "  ",
            matchingType: matchingType
        )
        #expect(emptyName?.contains("The model provider") == true)
    }

    @Test
    func nonHTTPErrorsProduceNoProviderMessage() {
        #expect(
            ProviderErrorClassifier.userFacingMessage(
                for: FakeUnrelatedError.broken,
                providerName: "OpenAI",
                matchingType: matchingType
            ) == nil
        )
    }

    @Test
    func fallbackWarningIncludesStatusWhenClassified() {
        let classified = ProviderErrorClassifier.fallbackWarning(
            for: httpError(500),
            fallback: "using fallback planning",
            matchingType: matchingType
        )
        #expect(classified == "Model provider returned HTTP 500 - using fallback planning.")

        let generic = ProviderErrorClassifier.fallbackWarning(
            for: FakeUnrelatedError.broken,
            fallback: "using your original prompt",
            matchingType: matchingType
        )
        #expect(generic == "The selected model failed - using your original prompt.")
    }
}
