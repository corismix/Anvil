import AnyLanguageModel
import Foundation

@Generable(description: "Coverage report comparing a generated app against the user's request.")
struct GeneratedToolCoverageReport {
    @Guide(
        description:
            "Requested features, states, or behaviors with no trace anywhere in the app source, or an empty list."
    )
    let missingFeatures: [String]
}

struct ToolCoverageClient: Sendable {
    private var checkForRequest:
        @Sendable (_ brief: String, _ source: String, _ invoker: ToolLanguageModelInvoker) async -> [String]?

    init(
        _ check: @escaping @Sendable (_ brief: String, _ source: String, _ invoker: ToolLanguageModelInvoker) async -> [String]?
    ) {
        self.checkForRequest = check
    }

    func missingFeatures(
        brief: String,
        source: String,
        invoker: ToolLanguageModelInvoker
    ) async -> [String]? {
        await checkForRequest(brief, source, invoker)
    }

    static func disabled() -> Self {
        Self { _, _, _ in nil }
    }

    static func live() -> Self {
        Self { brief, source, invoker in
            do {
                let session = invoker.makeSession(
                    for: .codingAgent,
                    instructions: coverageCheckInstructions
                )
                let response = try await invoker.respond(
                    stage: .codingAgent,
                    in: session,
                    to: coverageCheckPrompt(brief: brief, source: source),
                    generating: GeneratedToolCoverageReport.self
                )
                let missing = response.missingFeatures
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                AgentDiagnosticsLog.append(
                    """
                    Tool coverage check completed.
                    brief: \(AgentDiagnosticsLog.compact(brief, limit: 240))
                    missingCount: \(missing.count)
                    missing: \(AgentDiagnosticsLog.compact(missing.joined(separator: "; "), limit: 800))
                    """
                )
                return missing
            } catch {
                AgentDiagnosticsLog.append(
                    """
                    Tool coverage check failed; skipping coverage repair.
                    brief: \(AgentDiagnosticsLog.compact(brief, limit: 240))
                    error:
                    \(AgentDiagnosticsLog.renderError(error, limit: 500))
                    """
                )
                return nil
            }
        }
    }

    nonisolated static let coverageCheckInstructions = """
        You verify that a generated macOS SwiftUI app implements everything the user requested.
        Compare the user's request against the app's Swift source code.
        Report only requested features, states, or behaviors that have no trace anywhere in the source.
        When in doubt, treat the request as implemented.
        Items the request explicitly defers to a later version are intentionally out of scope; never report them.
        Never report style, quality, naming, or improvement suggestions.
        Report each missing item as a short phrase.
        Use an empty list when everything requested is present.
        """

    nonisolated static func coverageCheckPrompt(brief: String, source: String) -> String {
        """
        User request:
        \(brief)

        App source:
        \(source)
        """
    }

    nonisolated static func coverageGapEditPrompt(missingFeatures: [String]) -> String {
        """
        The app compiles, but a coverage check against the user's request found these requested items have no implementation:
        \(missingFeatures.map { "- \($0)" }.joined(separator: "\n"))

        Add each missing item now, preserving all existing behavior, structure, and visual design that already works.
        """
    }
}
