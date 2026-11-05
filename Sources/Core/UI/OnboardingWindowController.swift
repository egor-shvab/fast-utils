import AppKit
import Combine
import SwiftUI

/// The first-launch window (TZ.md §9): what the app does, its shortcuts, permissions,
/// open-at-login. Shown once; the same permissions list lives in Settings.
@MainActor
public final class OnboardingWindowController {
    private let registry: FeatureRegistry
    private let context: AppContext
    private var window: NSWindow?

    private var completed: Bool {
        get { context.settings.app.value("onboarding.completed", default: false) }
        set { context.settings.app.set(newValue, for: "onboarding.completed") }
    }

    public init(registry: FeatureRegistry, context: AppContext) {
        self.registry = registry
        self.context = context
    }

    public func showIfNeeded() {
        if !completed { show() }
    }

    public func show() {
        if window == nil {
            let model = OnboardingModel()
            let view = OnboardingView(registry: registry, context: context, model: model) { [weak self] in
                self?.finish(launchAtLogin: model.launchAtLogin)
            }
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = String(localized: "onboarding.window.title")
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    private func finish(launchAtLogin: Bool) {
        if launchAtLogin != context.launchAtLogin.isEnabled {
            context.launchAtLogin.setEnabled(launchAtLogin)
        }
        completed = true
        window?.close()
        window = nil
    }
}

/// Not `@State` — see CLAUDE.md (SwiftUI macros without Xcode).
@MainActor
final class OnboardingModel: ObservableObject {
    @Published var launchAtLogin = true
}

struct OnboardingView: View {
    let registry: FeatureRegistry
    let context: AppContext
    @ObservedObject var model: OnboardingModel
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "onboarding.title")).font(.title2.bold())
                    Text(String(localized: "onboarding.subtitle")).foregroundStyle(.secondary)
                }
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(actionRows, id: \.id) { row in
                        HStack {
                            Image(systemName: row.icon).frame(width: 22).foregroundStyle(.secondary)
                            Text(row.title)
                            Spacer()
                            Text(row.shortcut).monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                    Text(String(localized: "onboarding.shortcutsHint"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(6)
            } label: {
                Text(String(localized: "onboarding.shortcuts"))
            }

            if !registry.requiredPermissions.isEmpty {
                GroupBox {
                    VStack(alignment: .leading, spacing: 4) {
                        PermissionsList(permissions: registry.requiredPermissions, service: context.permissions)
                    }
                    .padding(6)
                } label: {
                    Text(String(localized: "onboarding.permissions"))
                }
            }

            Toggle(String(localized: "settings.general.launchAtLogin"), isOn: $model.launchAtLogin)

            HStack {
                Spacer()
                Button(String(localized: "onboarding.done"), action: onDone)
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
            }
        }
        .padding(24)
        .frame(width: 560)
    }

    private struct ActionRow {
        let id: ActionID
        let title: String
        let icon: String
        let shortcut: String
    }

    private var actionRows: [ActionRow] {
        registry.features.filter { registry.isEnabled(FeatureRegistry.id(of: $0)) }.flatMap { feature in
            feature.actions.map { action in
                ActionRow(
                    id: action.id, title: action.title, icon: feature.icon,
                    shortcut: context.hotkeys.shortcut(for: action.id)?.description
                        ?? String(localized: "shortcut.recorder.none")
                )
            }
        }
    }
}
