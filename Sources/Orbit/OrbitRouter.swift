/// Imperative commands for the stack or flow containing a screen.
///
/// Read a library-provided router with `@Environment(\.orbit)`. It targets the
/// screen's stack, not necessarily the root's selected tab. Custom conformances
/// can be injected into standalone screen previews or used as test spies.
/// Commands are synchronous main-actor state requests; success does not mean a
/// SwiftUI transition has finished. A fully retired library router returns
/// `false` for fallible commands instead of navigating another flow.
@MainActor
public protocol OrbitRouter: AnyObject {
    /// Replaces the scene root through the owning Orbit.
    ///
    /// Preserves active modals; retires old root/tab navigation paths. Root
    /// replacement is scene-wide even when requested from a modal screen.
    /// - Parameter route: A registered root route; fresh instances reset view ID.
    /// - Returns: `true` if accepted; otherwise `false`, subject to diagnostics.
    @discardableResult func setRoot(_ route: OrbitRoute) -> Bool

    /// Appends a destination to this router's stack.
    ///
    /// Does not select a tab or change a different stack. A non-stack root/modal,
    /// a closing modal, an unregistered type, a repeated instance in this path
    /// or an independent tab-flow route cannot be pushed.
    /// - Parameter route: A fresh registered destination instance.
    /// - Returns: `true` if accepted; otherwise `false`, subject to diagnostics.
    @discardableResult func push(_ route: OrbitRoute) -> Bool

    /// Removes the last pushed destination from this stack; an empty path is a no-op.
    func pop()

    /// Clears pushed destinations, revealing this stack's root; does not dismiss it.
    func popToRoot()

    /// Removes destinations after the last occurrence of an exact route type.
    ///
    /// Keeps the matched destination. Does nothing if no pushed entry matches;
    /// the root screen is not a path entry. Subclasses do not match a base type.
    /// - Parameter type: Exact route type to find in the current path.
    func popTo(_ type: OrbitRoute.Type)

    /// Removes destinations after an exact route instance, retaining that entry.
    ///
    /// Does nothing if the instance is absent; equal payloads do not match.
    /// - Parameter route: Instance already present in this router's path.
    func popTo(_ route: OrbitRoute)

    /// Selects a tab in this router's nearest tab container.
    ///
    /// Modal tab flows use their own container. An ordinary modal inherits the
    /// tab scope of its presenter. This does not dismiss modals or affect other
    /// tabs' stacks. Outside a tab scope the library reports a rejected request.
    /// - Parameters:
    ///   - tab: Declared tab, matched by exact Swift type.
    ///   - path: `nil` preserves its path, an array replaces it, and `[]` clears it.
    ///     All entries must be registered, distinct instances and non-tab flows.
    /// - Returns: `true` if accepted; otherwise `false`, subject to diagnostics.
    @discardableResult func selectTab(
        _ tab: OrbitTab,
        replacingPath path: [OrbitRoute]?
    ) -> Bool
    /// Requests a modal above this flow's active presentation chain.
    ///
    /// Tab routers delegate to their enclosing flow host, so the first modal
    /// covers its tab container. Nested modals have separate routers and paths.
    /// - Parameters:
    ///   - route: Registered destination; an independent tab flow is allowed.
    ///   - style: Native sheet or iOS-only full-screen cover.
    /// - Returns: `true` if accepted, not if already visible. Returns `false`
    ///   for validation failure, an unsupported style or a closing flow, subject
    ///   to diagnostics. Requests are not queued.
    @discardableResult func present(
        _ route: OrbitRoute,
        style: OrbitPresentationStyle
    ) -> Bool
    /// Requests dismissal of this router's modal flow, independently of style.
    ///
    /// A router in a modal tab closes its enclosing modal, not its individual
    /// stack. A root router instead closes the modal it presents. A nested
    /// modal closes itself and descendants, leaving its parent open. With no
    /// applicable presentation this is a no-op; it never acts as a stack pop.
    func dismiss()
}

extension OrbitRouter {
    /// Selects a declared tab without replacing its existing path.
    ///
    /// Equivalent to `selectTab(tab, replacingPath: nil)` in the same scope.
    /// - Parameter tab: Tab to select, matched by exact Swift type.
    /// - Returns: Whether selection was accepted, subject to diagnostics.
    @discardableResult
    public func selectTab(_ tab: OrbitTab) -> Bool {
        selectTab(tab, replacingPath: nil)
    }

    /// Requests a native sheet in this router's presentation scope.
    ///
    /// Equivalent to `present(route, style: .sheet)`.
    /// - Parameter route: Registered modal destination.
    /// - Returns: Whether the request was accepted, not animation completion.
    @discardableResult
    public func present(_ route: OrbitRoute) -> Bool {
        present(route, style: .sheet)
    }
}
