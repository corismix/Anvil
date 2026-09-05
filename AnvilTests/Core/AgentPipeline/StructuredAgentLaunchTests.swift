import Foundation
import Testing
@testable import Anvil

struct StructuredAgentLaunchTests {
    @Test
    func resolvesAbsoluteAndPATHExecutables() {
        let absolute = StructuredAgentLaunchResolver.resolveExecutable(
            "/opt/tools/agent",
            pathEnvironment: "/usr/bin",
            homeDirectory: URL(fileURLWithPath: "/home/test"),
            isExecutableFile: { $0 == "/opt/tools/agent" }
        )
        #expect(absolute == URL(fileURLWithPath: "/opt/tools/agent"))

        let onPath = StructuredAgentLaunchResolver.resolveExecutable(
            "agent",
            pathEnvironment: "/usr/bin:/custom/bin",
            homeDirectory: URL(fileURLWithPath: "/home/test"),
            isExecutableFile: { $0 == "/custom/bin/agent" }
        )
        #expect(onPath == URL(fileURLWithPath: "/custom/bin/agent"))

        let missing = StructuredAgentLaunchResolver.resolveExecutable(
            "agent",
            pathEnvironment: "/usr/bin",
            homeDirectory: URL(fileURLWithPath: "/home/test"),
            isExecutableFile: { _ in false }
        )
        #expect(missing == nil)
    }

    @Test
    func promptTokenReplacesInsideSingleArgument() {
        let launch = StructuredAgentLaunch(
            executable: "agent",
            arguments: ["--prompt={{prompt}}", "--fast"]
        )
        let resolved = StructuredAgentLaunchResolver.resolvedArguments(
            launch,
            prompt: "Build a timer; ignore $HOME && everything"
        )
        #expect(!resolved.promptViaStandardInput)
        #expect(
            resolved.arguments == [
                "--prompt=Build a timer; ignore $HOME && everything",
                "--fast",
            ]
        )
    }

    @Test
    func promptFallsBackToStandardInputWithoutToken() {
        let launch = StructuredAgentLaunch(executable: "agent", arguments: ["--work"])
        let resolved = StructuredAgentLaunchResolver.resolvedArguments(launch, prompt: "hi")
        #expect(resolved.promptViaStandardInput)
        #expect(resolved.arguments == ["--work"])
    }

    @Test
    func environmentMergesOverMinimalBase() {
        let launch = StructuredAgentLaunch(
            executable: "agent",
            environment: ["API_URL": "https://example.test", "PATH": "/custom/bin"]
        )
        let merged = StructuredAgentLaunchResolver.mergedEnvironment(
            launch,
            base: ["PATH": "/usr/bin", "HOME": "/home/test", "SECRET": "shh", "LANG": "en_US"]
        )
        #expect(merged["PATH"] == "/custom/bin")
        #expect(merged["HOME"] == "/home/test")
        #expect(merged["API_URL"] == "https://example.test")
        #expect(merged["LANG"] == "en_US")
        #expect(merged["SECRET"] == nil)
    }

    @Test
    func legacyParseAcceptsCleanCommands() {
        let parsed = StructuredAgentLaunchResolver.parseLegacyCommand(
            "agent run --prompt {{prompt}}"
        )
        #expect(
            parsed == StructuredAgentLaunch(
                executable: "agent",
                arguments: ["run", "--prompt", "{{prompt}}"]
            )
        )

        let quoted = StructuredAgentLaunchResolver.parseLegacyCommand(
            "agent run --name \"my agent\" {{prompt}}"
        )
        #expect(quoted?.arguments == ["run", "--name", "my agent", "{{prompt}}"])
    }

    @Test
    func legacyParseRejectsShellFeatures() {
        for command in [
            "agent run | tee log",
            "agent run > out.txt",
            "agent run && echo done",
            "agent run $HOME",
            "cat `which agent`",
            "agent run; rm -rf x",
        ] {
            #expect(StructuredAgentLaunchResolver.parseLegacyCommand(command) == nil)
        }
    }

    @Test
    func validationRejectsBadLaunches() {
        #expect(throws: StructuredAgentLaunchError.missingExecutable) {
            try StructuredAgentLaunchResolver.validate(
                StructuredAgentLaunch(executable: "  "),
                isExecutableFile: { _ in true }
            )
        }
        #expect(throws: StructuredAgentLaunchError.executableNotFound("nope")) {
            try StructuredAgentLaunchResolver.validate(
                StructuredAgentLaunch(executable: "nope"),
                isExecutableFile: { _ in false }
            )
        }
        #expect(throws: StructuredAgentLaunchError.invalidEnvironmentKey("1BAD")) {
            try StructuredAgentLaunchResolver.validate(
                StructuredAgentLaunch(executable: "agent", environment: ["1BAD": "x"]),
                isExecutableFile: { _ in true }
            )
        }
    }
}
