import Combine
import SwiftUI

/// Temporary panel content for stub features (until stages 6–7). Exercises the panel
/// behavior: keyboard input without activating the app, pinning, Esc, click outside.
public struct StubPanelView: View {
    let title: String
    let text: String
    let showsSearch: Bool
    @Bindable var handle: PanelHandle
    @StateObject private var model = StubPanelModel()
    @FocusState private var searchFocused: Bool

    public init(title: String, text: String, showsSearch: Bool = false, handle: PanelHandle) {
        self.title = title
        self.text = text
        self.showsSearch = showsSearch
        self.handle = handle
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Toggle(isOn: $handle.isPinned) { Image(systemName: handle.isPinned ? "pin.fill" : "pin") }
                    .toggleStyle(.button)
                    .buttonStyle(.borderless)
                    .help(String(localized: "panel.pin"))
            }
            if showsSearch {
                TextField(String(localized: "stub.search"), text: $model.query)
                    .textFieldStyle(.roundedBorder)
                    .focused($searchFocused)
                if !model.query.isEmpty {
                    Text(String(format: String(localized: "stub.typed"), model.query))
                        .foregroundStyle(.secondary)
                }
            }
            Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Text(String(localized: "panel.hint")).font(.caption).foregroundStyle(.tertiary)
        }
        .padding(16)
        .padding(.top, 8)
        .onAppear { searchFocused = showsSearch }
    }
}

@MainActor
final class StubPanelModel: ObservableObject {
    @Published var query = ""
}
