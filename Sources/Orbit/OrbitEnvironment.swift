import SwiftUI

/// Adds Orbit's screen-scoped router dependency to SwiftUI's environment.
extension EnvironmentValues {
    @Entry private var orbitRouter: (any OrbitRouter)? = nil
    @Entry var orbitContext: OrbitContext? = nil

    /// The imperative router for the screen's enclosing navigation stack/flow.
    ///
    /// Use `@Environment(\.orbit)` in destination views. Orbit's hosts install
    /// the appropriate router; it is not a scene-wide implicit push target.
    /// Set a custom ``OrbitRouter`` with `.environment(\.orbit, router)` for a
    /// standalone screen preview or test. Hosts install their own routers
    /// inside their content, so inject overrides at the destination when needed.
    ///
    /// Outside a host, reading this value is allowed. Invoking a command on its
    /// fallback asserts in debug; in release fallible commands return `false`
    /// and void commands do nothing. There is no owner to receive rejection events.
    @MainActor
    public var orbit: any OrbitRouter {
        get { orbitRouter ?? MissingOrbitRouter.shared }
        set { orbitRouter = newValue }
    }
}

@MainActor
private final class MissingOrbitRouter: OrbitRouter {
    static let shared = MissingOrbitRouter()

    private func missing() -> Bool {
        assertionFailure("Install OrbitRootHost before invoking navigation commands.")
        return false
    }

    func setRoot(_ route: OrbitRoute) -> Bool { missing() }
    func push(_ route: OrbitRoute) -> Bool { missing() }
    func pop() { _ = missing() }
    func popToRoot() { _ = missing() }
    func popTo(_ type: OrbitRoute.Type) { _ = missing() }
    func popTo(_ route: OrbitRoute) { _ = missing() }
    func selectTab(_ tab: OrbitTab, replacingPath path: [OrbitRoute]?) -> Bool {
        missing()
    }
    func present(_ route: OrbitRoute, style: OrbitPresentationStyle) -> Bool {
        missing()
    }
    func dismiss() { _ = missing() }
}
