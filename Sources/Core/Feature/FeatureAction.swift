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
    /// Only for other features (chains): not shown in the menu, shortcuts or onboarding.
    public let isInternal: Bool
    public let perform: @MainActor (ActionInput) async throws -> ActionOutput

    public init(
        id: ActionID,
        title: String,
        defaultShortcut: Shortcut? = nil,
        isInternal: Bool = false,
        perform: @escaping @MainActor (ActionInput) async throws -> ActionOutput
    ) {
        self.id = id
        self.title = title
        self.defaultShortcut = defaultShortcut
        self.isInternal = isInternal
        self.perform = perform
    }
}

/// An entry in the status bar menu. Built each time the menu opens, so it can reflect state.
@MainActor
public struct MenuItemDescriptor {
    public let title: String
    /// Runs this action; its shortcut is shown next to the item.
    public let actionID: ActionID?
    /// Runs this closure instead of an action (state toggles that need no hotkey).
    public let handler: (@MainActor () -> Void)?
    public let isChecked: Bool
    public let isEnabled: Bool
    public let submenu: [MenuItemDescriptor]

    public init(actionID: ActionID, title: String) {
        self.init(title: title, actionID: actionID, handler: nil, isChecked: false, isEnabled: true, submenu: [])
    }

    init(title: String, actionID: ActionID?, handler: (@MainActor () -> Void)?, isChecked: Bool, isEnabled: Bool,
         submenu: [MenuItemDescriptor]) {
        self.title = title
        self.actionID = actionID
        self.handler = handler
        self.isChecked = isChecked
        self.isEnabled = isEnabled
        self.submenu = submenu
    }

    public static func custom(_ title: String, isChecked: Bool = false, handler: @escaping @MainActor () -> Void) -> Self {
        Self(title: title, actionID: nil, handler: handler, isChecked: isChecked, isEnabled: true, submenu: [])
    }

    public static func label(_ title: String) -> Self {
        Self(title: title, actionID: nil, handler: nil, isChecked: false, isEnabled: false, submenu: [])
    }

    public static func submenu(_ title: String, _ items: [MenuItemDescriptor]) -> Self {
        Self(title: title, actionID: nil, handler: nil, isChecked: false, isEnabled: true, submenu: items)
    }
}
