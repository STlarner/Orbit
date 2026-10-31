import SwiftUI

@MainActor
final class RouteRegistry {
    struct Registration {
        let navigation: OrbitNavigationMode
        let factory: @MainActor (OrbitRoute) -> AnyView
    }

    private var registrations: [ObjectIdentifier: Registration] = [:]

    func register<R: OrbitRoute, V: View>(
        _ type: R.Type,
        navigation: OrbitNavigationMode,
        factory: @escaping @MainActor (R) -> V
    ) -> Bool {
        let key = ObjectIdentifier(type)
        guard registrations[key] == nil else { return false }
        registrations[key] = Registration(navigation: navigation) { route in
            guard let typed = route as? R else {
                return AnyView(EmptyView())
            }
            return AnyView(factory(typed))
        }
        return true
    }

    func registration(for route: OrbitRoute) -> Registration? {
        registrations[ObjectIdentifier(type(of: route))]
    }
}
