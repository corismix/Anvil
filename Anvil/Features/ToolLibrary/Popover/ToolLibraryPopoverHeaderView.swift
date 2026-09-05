import AppKit
import SwiftUI

struct ToolLibraryPopoverHeaderView: View {
    @Environment(\.openURL) private var openURL
    @Binding var isSearchPresented: Bool
    @Binding var searchText: String
    @Binding var viewMode: ToolLibraryViewMode
    @Binding var sortOrder: ToolLibrarySortOrder
    @FocusState private var isSearchFieldFocused: Bool

    let appUpdateStore: AppUpdateStore
    let isLoadingModels: Bool
    let onOpenSettings: () -> Void
    private static let issueReportURL = URL(
        string: "https://github.com/corismix/Anvil/issues/new")!

    var body: some View {
        HStack {
            headerLeadingContent
                .layoutPriority(1)

            Spacer()

            if !isSearchPresented && appUpdateStore.shouldShowUpdateButton {
                Button("Update") {
                    appUpdateStore.openAvailableUpdate()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .help("Open latest release")
                .accessibilityIdentifier("app-update-button")
            }

            Button(action: toggleSearch) {
                Image(systemName: isSearchPresented ? "xmark" : "magnifyingglass")
                    .font(.system(size: 15, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(isSearchPresented ? "Close Search" : "Search Apps")
            .accessibilityLabel(isSearchPresented ? "Close app search" : "Search apps")
            .accessibilityIdentifier("tool-search-button")

            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 15, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Settings")
            .accessibilityLabel("Settings")
            .accessibilityIdentifier("settings-button")

            Menu {
                Menu("View") {
                    ForEach(ToolLibraryViewMode.allCases) { mode in
                        Button {
                            viewMode = mode
                        } label: {
                            Label(
                                mode.title,
                                systemImage: viewMode == mode ? "checkmark" : mode.systemImage
                            )
                        }
                    }

                    Divider()

                    Menu("Sort By") {
                        ForEach(ToolLibrarySortOrder.allCases) { order in
                            Button {
                                sortOrder = order
                            } label: {
                                Label(
                                    order.title,
                                    systemImage: sortOrder == order
                                        ? "checkmark"
                                        : sortSystemImage(for: order)
                                )
                            }
                        }
                    }
                }

                Divider()

                Button("About Anvil") {
                    AnvilAboutWindowController.shared.show()
                }

                Button("Report an Issue") {
                    openURL(Self.issueReportURL)
                }

                Divider()

                Button("Quit Anvil") {
                    NSApp.terminate(nil)
                }
            } label: {
                Image(systemName: "line.3.horizontal.circle")
                    .font(.system(size: 15, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Anvil")
            .accessibilityLabel("Anvil menu")
            .accessibilityHint("Opens about, issue reporting, and quit actions.")
            .accessibilityIdentifier("anvil-menu-button")
        }
        .onChange(of: isSearchPresented) { _, isPresented in
            isSearchFieldFocused = isPresented
        }
    }

    @ViewBuilder
    private var headerLeadingContent: some View {
        if isSearchPresented {
            searchField
                .transition(.opacity.combined(with: .move(edge: .trailing)))
        } else {
            leadingContent
                .transition(.opacity)
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            TextField("Search apps", text: $searchText)
                .textFieldStyle(.plain)
                .focused($isSearchFieldFocused)
                .onExitCommand(perform: closeSearch)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    isSearchFieldFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Clear Search")
                .accessibilityLabel("Clear app search")
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
        .frame(maxWidth: .infinity)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 7))
        .accessibilityIdentifier("tool-search-field")
    }

    @ViewBuilder
    private var leadingContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Anvil")
                .font(.headline.weight(.semibold))
                .lineLimit(1)

            if shouldShowModelStatus {
                modelStatus
                    .frame(height: 18, alignment: .topLeading)
            }
        }
    }

    @ViewBuilder
    private var modelStatus: some View {
        if isLoadingModels {
            HStack(spacing: 5) {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
                    .accessibilityLabel("Loading AI model")

                Text("Loading AI model…")
                    .lineLimit(1)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
        }
    }

    private var shouldShowModelStatus: Bool {
        isLoadingModels
    }

    private func toggleSearch() {
        withAnimation(.easeInOut(duration: 0.16)) {
            if isSearchPresented {
                closeSearch()
            } else {
                isSearchPresented = true
            }
        }
    }

    private func closeSearch() {
        searchText = ""
        isSearchPresented = false
        isSearchFieldFocused = false
    }

    private func sortSystemImage(for order: ToolLibrarySortOrder) -> String {
        switch order {
        case .latest:
            return "clock"
        case .alphabetical:
            return "textformat"
        }
    }
}
