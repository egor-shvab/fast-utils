import SwiftUI

/// A feature module (OCR, translation, clipboard history, …).
///
/// To add a feature: create a `Feature*` target that depends only on `Core`, implement this
/// protocol and add the type to `FeatureList.swift`. Core then provides the on/off switch,
/// menu items, a settings tab and lifecycle calls. Features never import each other;
/// they talk through `ActionRegistry` and `EventBus`.
@MainActor
public protocol Feature: AnyObject {
    static var id: FeatureID { get }

    var title: String { get }
    /// SF Symbol name.
    var icon: String { get }
    var requiredPermissions: Set<Permission> { get }
    var actions: [FeatureAction] { get }
    var menuItems: [MenuItemDescriptor] { get }
    /// Content of the feature's tab in Settings; `nil` means no tab.
    var settingsView: AnyView? { get }

    /// Must be cheap: every feature is created at launch, enabled or not.
    init(context: AppContext)
    /// Called when the feature is turned on (including at launch). Acquire resources here.
    func start() async
    /// Called when the feature is turned off. Release everything acquired in `start()`.
    func stop() async
}

public extension Feature {
    var requiredPermissions: Set<Permission> { [] }
    var menuItems: [MenuItemDescriptor] {
        actions.filter { !$0.isInternal }.map { MenuItemDescriptor(actionID: $0.id, title: $0.title) }
    }
    var settingsView: AnyView? { nil }
    func start() async {}
    func stop() async {}
}
