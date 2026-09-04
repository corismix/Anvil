import Foundation

struct InferenceDependencies {
    var credentialClient: CredentialClient
    var openAICodexAuthClient: OpenAICodexAuthClient
    var remoteModelClient: RemoteModelClient
    var localModelClient: LocalModelClient
    var ollamaClient: OllamaClient
    var languageModelClient: LanguageModelClient

    init(
        credentialClient: CredentialClient,
        openAICodexAuthClient: OpenAICodexAuthClient = .unconfigured,
        remoteModelClient: RemoteModelClient,
        localModelClient: LocalModelClient,
        ollamaClient: OllamaClient,
        languageModelClient: LanguageModelClient
    ) {
        self.credentialClient = credentialClient
        self.openAICodexAuthClient = openAICodexAuthClient
        self.remoteModelClient = remoteModelClient
        self.localModelClient = localModelClient
        self.ollamaClient = ollamaClient
        self.languageModelClient = languageModelClient
    }
}

extension InferenceDependencies {
    static var live: Self {
        let credentialClient = CredentialClient.live
        let localModelClient = LocalModelClient.live
        let openAICodexAuthClient = OpenAICodexAuthClient.live()
        return Self(
            credentialClient: credentialClient,
            openAICodexAuthClient: openAICodexAuthClient,
            remoteModelClient: .live(
                openAICodexAuthClient: openAICodexAuthClient
            ),
            localModelClient: localModelClient,
            ollamaClient: .live,
            languageModelClient: .live(
                credentialClient: credentialClient,
                localModelClient: localModelClient,
                openAICodexAuthClient: openAICodexAuthClient
            )
        )
    }
}
