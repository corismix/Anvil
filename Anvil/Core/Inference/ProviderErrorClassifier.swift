import Foundation

/// Classifies transport-level provider failures (HTTP status codes) so
/// generation errors can tell the user what to actually do - sign in again,
/// wait out a rate limit, or retry later - instead of showing a raw
/// `AnyLanguageModel.URLSessionError`.
nonisolated enum ProviderErrorClassifier {
    /// The AnyLanguageModel error type that carries HTTP failures. It is
    /// internal to the package, so the status code is read via reflection
    /// (the same approach as AgentDiagnosticsLog.renderError).
    static let urlSessionErrorTypeName = "AnyLanguageModel.URLSessionError"

    /// Extracts the HTTP status code from a provider error, following
    /// NSUnderlyingErrorKey wrapping. Returns nil for non-HTTP errors.
    static func httpStatusCode(
        from error: any Error,
        matchingType typeName: String = urlSessionErrorTypeName
    ) -> Int? {
        if let statusCode = reflectedHTTPStatusCode(from: error, matchingType: typeName) {
            return statusCode
        }
        let nsError = error as NSError
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? any Error {
            return httpStatusCode(from: underlying, matchingType: typeName)
        }
        return nil
    }

    /// User-facing message for a provider HTTP failure, naming the provider
    /// when known. Returns nil when the error is not a provider HTTP error.
    static func userFacingMessage(
        for error: any Error,
        providerName: String?,
        matchingType typeName: String = urlSessionErrorTypeName
    ) -> String? {
        guard let statusCode = httpStatusCode(from: error, matchingType: typeName) else {
            return nil
        }
        let trimmed = providerName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let provider = trimmed.isEmpty ? "The model provider" : trimmed
        switch statusCode {
        case 401, 403:
            return "\(provider) rejected the request (HTTP \(statusCode)). Your sign-in may have expired - sign in again in Settings, then retry."
        case 429:
            return "\(provider) rate limited the request (HTTP 429). Wait a moment, then retry."
        case 500 ... 599:
            return "\(provider) is erroring (HTTP \(statusCode)). That is on their side, not your prompt - retry in a bit. If it keeps failing, sign out and back in in Settings."
        default:
            return "\(provider) returned HTTP \(statusCode). Retry, or check your provider connection in Settings."
        }
    }

    /// Short warning shown when a generation stage falls back because the
    /// selected model failed (for example planning on the on-device model).
    static func fallbackWarning(
        for error: any Error,
        fallback: String,
        matchingType typeName: String = urlSessionErrorTypeName
    ) -> String {
        if let statusCode = httpStatusCode(from: error, matchingType: typeName) {
            return "Model provider returned HTTP \(statusCode) - \(fallback)."
        }
        return "The selected model failed - \(fallback)."
    }

    /// `.httpError(statusCode:detail:)` mirrors as a single child labeled
    /// "httpError" whose value is the labeled associated-value tuple.
    private static func reflectedHTTPStatusCode(
        from error: any Error,
        matchingType typeName: String
    ) -> Int? {
        guard String(reflecting: Swift.type(of: error)) == typeName else {
            return nil
        }
        for child in Mirror(reflecting: error).children where child.label == "httpError" {
            for associated in Mirror(reflecting: child.value).children
            where associated.label == "statusCode" {
                return associated.value as? Int
            }
        }
        return nil
    }
}
