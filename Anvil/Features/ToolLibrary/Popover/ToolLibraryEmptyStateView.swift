import SwiftUI

struct ToolLibraryEmptyStateView: View {
    let showsNoModelActions: Bool

    init(showsNoModelActions: Bool = false) {
        self.showsNoModelActions = showsNoModelActions
    }

    var body: some View {
        VStack(spacing: 10) {
            Image("ProviderLogoAnvil")
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .foregroundStyle(.secondary)
                .frame(width: 50, height: 50)
                .accessibilityHidden(true)

            Text(title)
                .font(.title3.weight(.semibold))

            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 288)
    }

    private var title: String {
        showsNoModelActions ? "No AI models" : "No apps yet"
    }

    private var message: String {
        if showsNoModelActions {
            return
                "No AI models are available. Add a provider in Settings to get started."
        }

        return
            "Create a new one from the prompt box below."
    }
}
