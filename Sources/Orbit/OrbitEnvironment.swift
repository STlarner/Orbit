import SwiftUI

extension EnvironmentValues {
    @Entry private var orbitRouter: (any OrbitRouter)? = nil
    @Entry public var orbitTabs: OrbitTabManager? = nil

    /// Installed by Orbit's hosts. Missing installation fails loudly only
    /// when a command is invoked, not when rendering a standalone preview.
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
        assertionFailure("Install OrbitRootHost or OrbitNavigationHost first.")
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
