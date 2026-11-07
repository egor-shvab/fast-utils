import Carbon.HIToolbox
import Core
import Observation
import OSLog
import SwiftUI

/// Color picker: a loupe over the frozen screen; the picked color goes to the clipboard.
public final class ColorFeature: Feature {
    public static let id: FeatureID = "color"

    private let context: AppContext
    private let log: Logger
    let settings: ColorSettings
    private var isRunning = false

    public init(context: AppContext) {
        self.context = context
        log = context.logger(Self.id.rawValue)
        settings = ColorSettings(store: context.settings.scoped(Self.id))
    }

    public var title: String { String(localized: "feature.color.title") }
    public var icon: String { "eyedropper" }
    public var summary: String { String(localized: "feature.color.summary") }
    public var tint: Color { .pink }
    public var requiredPermissions: Set<Permission> { [.screenRecording, .pasteboard] }

    public var actions: [FeatureAction] {
        [
            FeatureAction(
                id: "color.pick",
                title: String(localized: "color.action.pick"),
                defaultShortcut: Shortcut(kVK_ANSI_P, [.option, .command])
            ) { [weak self] _ in
                await self?.pick()
                return .none
            },
        ]
    }

    public var settingsView: AnyView? { AnyView(ColorSettingsView(settings: settings)) }

    func pick() async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        let format = settings.format
        let color: Core.RGBColor
        do {
            guard let picked = try await context.colorPicker.pickColor(label: format.format) else { return }
            color = picked
        } catch ScreenCaptureError.notPermitted {
            log.error("Screen capture: no Screen Recording permission")
            context.permissions.request(.screenRecording)
            context.hud.show(String(localized: "color.hud.noPermission"), style: .error)
            return
        } catch {
            log.error("Screen capture failed: \(String(describing: error), privacy: .public)")
            context.hud.show(String(localized: "color.hud.captureFailed"), style: .error)
            return
        }
        let value = format.format(color)
        context.pasteboard.writeText(value)
        context.hud.show(String(localized: "color.hud.copied"), detail: value, swatch: color)
    }
}

/// Preferences, persisted under `color.*`.
@MainActor
@Observable
final class ColorSettings {
    var format: ColorFormat { didSet { store.set(format.rawValue, for: "format") } }

    @ObservationIgnored private let store: ScopedSettings

    init(store: ScopedSettings) {
        self.store = store
        format = ColorFormat(rawValue: store.value("format", default: "")) ?? .hexLower
    }
}

struct ColorSettingsView: View {
    @Bindable var settings: ColorSettings
    /// The examples in the picker show this color.
    private let sample = Core.RGBColor(red: 58, green: 123, blue: 213)

    var body: some View {
        Group {
            Section {
                Picker(String(localized: "color.settings.format"), selection: $settings.format) {
                    ForEach(ColorFormat.allCases, id: \.self) { format in
                        Text(format.format(sample)).font(.body.monospaced()).tag(format)
                    }
                }
            } footer: {
                Text(String(localized: "color.settings.footer"))
            }
        }
    }
}
