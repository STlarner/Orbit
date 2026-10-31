import SwiftUI

@MainActor
final class RouteRegistry {
    struct Registration {
        let navigation: OrbitNavigationMode
        let factory: @MainActor (OrbitRoute) -> AnyView
        let tabsFactory: (@MainActor (OrbitRoute) -> PreparedTabFlow)?
    }

    private var registrations: [ObjectIdentifier: Registration] = [:]

    func register<R: OrbitRoute, V: View>(
        _ type: R.Type,
        navigation: OrbitNavigationMode,
        factory: @escaping @MainActor (R) -> V
    ) -> Bool {
        // Generic forwarding may hide the concrete public overload. Check
        // result-type metadata, never the rendered view hierarchy.
        let key = ObjectIdentifier(type)
        guard registrations[key] == nil else { return false }
        if V.self is any OrbitTabFlow.Type {
            registrations[key] = Registration(
                navigation: .content,
                factory: { _ in AnyView(EmptyView()) },
                tabsFactory: { route in
                    guard let typed = route as? R,
                        let flow = factory(typed) as? any OrbitTabFlow
                    else { return PreparedTabFlow(OrbitTabView {}) }
                    return PreparedTabFlow(flow)
                }
            )
            return true
        }
        registrations[key] = Registration(navigation: navigation, factory: { route in
            guard let typed = route as? R else {
                return AnyView(EmptyView())
            }
            return AnyView(factory(typed))
        }, tabsFactory: nil)
        return true
    }

    func registration(for route: OrbitRoute) -> Registration? {
        registrations[ObjectIdentifier(type(of: route))]
    }
}
