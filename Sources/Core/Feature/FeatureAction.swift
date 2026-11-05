import CoreGraphics

/// Data passed into an action. Lets actions be chained (OCR output → translate input).
public enum ActionInput {
    case none
    case text(String)
    case image(CGImage)
}

/// Data an action produces.
public enum ActionOutput {
    case none
    case text(String)
    case image(CGImage)
}

/// A unit of work a feature exposes: bindable to a hotkey or menu item,
/// and callable from other features through `ActionRegistry`.
@MainActor
public struct FeatureAction {
    public let id: ActionID
    public let title: String
    /// Global shortcut assigned on first launch; the user can change or clear it later.
    public let defaultShortcut: Shortcut?
    public let perform: @MainActor (ActionInput) async throws -> ActionOutput

    public init(
        id: ActionID,
        title: String,
        defaultShortcut: Shortcut? = nil,
        perform: @escaping @MainActor (ActionInput) async throws -> ActionOutput
    ) {
        self.id = id
        self.title = title
        self.defaultShortcut = defaultShortcut
        self.perform = perform
    }
}

/// An entry in the status bar menu that runs an action.
public struct MenuItemDescriptor: Sendable {
    public let actionID: ActionID
    public let title: String

    public init(actionID: ActionID, title: String) {
        self.actionID = actionID
        self.title = title
    }
}
