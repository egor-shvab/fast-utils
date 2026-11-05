import Foundation

public enum ActionError: Error, Equatable {
    /// No such action, or its feature is turned off.
    case notFound(ActionID)
}

/// All actions of currently enabled features. Lets one feature run another's action
/// without importing it: `try await context.actions.perform("translate.show", input: .text(s))`.
@MainActor
public final class ActionRegistry {
    private var actions: [ActionID: FeatureAction] = [:]
    private var owners: [ActionID: FeatureID] = [:]

    public init() {}

    func register(_ newActions: [FeatureAction], for feature: FeatureID) {
        for action in newActions {
            if let owner = owners[action.id], owner != feature {
                assertionFailure("Action \(action.id) already registered by \(owner)")
                continue
            }
            actions[action.id] = action
            owners[action.id] = feature
        }
    }

    func unregisterAll(for feature: FeatureID) {
        for (id, owner) in owners where owner == feature {
            actions[id] = nil
            owners[id] = nil
        }
    }

    public func action(_ id: ActionID) -> FeatureAction? { actions[id] }

    public func contains(_ id: ActionID) -> Bool { actions[id] != nil }

    @discardableResult
    public func perform(_ id: ActionID, input: ActionInput = .none) async throws -> ActionOutput {
        guard let action = actions[id] else { throw ActionError.notFound(id) }
        return try await action.perform(input)
    }
}
