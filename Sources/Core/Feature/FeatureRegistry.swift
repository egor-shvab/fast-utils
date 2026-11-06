import Foundation
import Observation

/// Owns all feature instances and their on/off state.
/// Turning a feature on registers its actions and calls `start()`; turning it off calls
/// `stop()` and removes its actions. The state is persisted (`features.<id>.enabled`).
@MainActor
@Observable
public final class FeatureRegistry {
    public let features: [any Feature]
    public private(set) var enabledIDs: Set<FeatureID> = []

    private let context: AppContext
    private let state: ScopedSettings

    public init(context: AppContext, types: [any Feature.Type]) {
        // Not `types.map(\.id)`: a key path to a static member through an existential
        // metatype crashes the Swift 6.4 compiler (SILGen).
        let ids = types.map { $0.id }
        precondition(Set(ids).count == ids.count, "Duplicate feature ids: \(ids)")
        self.context = context
        self.state = context.settings.scoped("features")
        self.features = types.map { $0.init(context: context) }
        for feature in features {
            context.hotkeys.declare(feature.actions)
        }
    }

    public static func id(of feature: any Feature) -> FeatureID { type(of: feature).id }

    public func feature(_ id: FeatureID) -> (any Feature)? {
        features.first { Self.id(of: $0) == id }
    }

    public func isEnabled(_ id: FeatureID) -> Bool { enabledIDs.contains(id) }

    /// Permissions needed by enabled features, in a stable order.
    public var requiredPermissions: [Permission] {
        let needed = features
            .filter { isEnabled(Self.id(of: $0)) }
            .reduce(into: Set<Permission>()) { $0.formUnion($1.requiredPermissions) }
        return Permission.allCases.filter(needed.contains)
    }

    /// Persisted preference; features are on by default.
    func isEnabledInSettings(_ id: FeatureID) -> Bool {
        state.value("\(id).enabled", default: true)
    }

    /// Starts every feature that is enabled in settings. Call once at launch.
    public func startEnabledFeatures() async {
        for feature in features where isEnabledInSettings(Self.id(of: feature)) {
            await activate(feature)
        }
    }

    public func setEnabled(_ enabled: Bool, for id: FeatureID) async {
        guard let feature = feature(id) else { return }
        state.set(enabled, for: "\(id).enabled")
        if enabled {
            await activate(feature)
        } else {
            await deactivate(feature)
        }
    }

    private func activate(_ feature: any Feature) async {
        let id = Self.id(of: feature)
        guard !enabledIDs.contains(id) else { return }
        enabledIDs.insert(id)
        context.actions.register(feature.actions, for: id)
        context.hotkeys.activate(feature.actions.map(\.id))
        await feature.start()
        context.logger("features").notice("Enabled \(id.rawValue, privacy: .public)")
    }

    private func deactivate(_ feature: any Feature) async {
        let id = Self.id(of: feature)
        guard enabledIDs.contains(id) else { return }
        enabledIDs.remove(id)
        context.hotkeys.deactivate(feature.actions.map(\.id))
        context.actions.unregisterAll(for: id)
        await feature.stop()
        context.logger("features").notice("Disabled \(id.rawValue, privacy: .public)")
    }
}
