import SwiftUI

@MainActor
final class RouteRegistry {
    struct Registration {
        let navigation: OrbitNavigationMode
        let factory: @MainActor (OrbitRoute) -> AnyView
        let tabsFactory: (@MainActor (OrbitRoute) -> OrbitTabView)?
    }

    private var registrations: [ObjectIdentifier: Registration] = [:]

    func register<R: OrbitRoute, V: View>(
        _ type: R.Type,
        navigation: OrbitNavigationMode,
        factory: @escaping @MainActor (R) -> V
    ) -> Bool {
        // Generic forwarding may hide the concrete public overload. Check
        // result-type metadata, never the rendered view hierarchy.
        if V.self == OrbitTabView.self {
            return registerTabs(type) { route in
                guard let tabs = factory(route) as? OrbitTabView else {
                    return OrbitTabView {}
                }
                return tabs
            }
        }
        let key = ObjectIdentifier(type)
        guard registrations[key] == nil else { return false }
        registrations[key] = Registration(navigation: navigation, factory: { route in
            guard let typed = route as? R else {
                return AnyView(EmptyView())
            }
            return AnyView(factory(typed))
        }, tabsFactory: nil)
        return true
    }

    func registerTabs<R: OrbitRoute>(
        _ type: R.Type,
        factory: @escaping @MainActor (R) -> OrbitTabView
    ) -> Bool {
        let key = ObjectIdentifier(type)
        guard registrations[key] == nil else { return false }
        registrations[key] = Registration(
            navigation: .content,
            factory: { _ in AnyView(EmptyView()) },
            tabsFactory: { route in
                // The registry is keyed by this exact type, so callers only
                // reach this factory after a successful type-key lookup.
                guard let typed = route as? R else {
                    return OrbitTabView {}
                }
                return factory(typed)
            }
        )
        return true
    }

    func registration(for route: OrbitRoute) -> Registration? {
        registrations[ObjectIdentifier(type(of: route))]
    }
}
