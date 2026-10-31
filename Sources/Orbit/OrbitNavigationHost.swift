import SwiftUI

/// A stack for a tab or a root/modal flow. Destination views do not own paths,
/// bindings or navigationDestination registration.
@MainActor
struct OrbitNavigationHost<Root: View>: View {
    private let context: OrbitContext
    private let root: () -> Root

    init(
        _ context: OrbitContext,
        @ViewBuilder root: @escaping () -> Root
    ) {
        self.context = context
        self.root = root
    }

    var body: some View {
        NavigationStack(path: Binding(
            get: { context.path },
            set: { _ = context.setPath($0) }
        )) {
            root()
                .navigationDestination(for: OrbitRoute.self) { route in
                    destination(route)
                }
        }
        .environment(\.orbit, context)
        .environment(\.orbitContext, context)
    }

    private func destination(_ route: OrbitRoute) -> AnyView {
        guard let registration = context.owner?.registry.registration(for: route)
        else {
            context.owner?.reject("Unregistered destination: \(route.name)")
            return AnyView(EmptyView())
        }
        return registration.factory(route)
    }
}

@MainActor
struct FlowContent: View {
    let route: OrbitRoute
    let context: OrbitContext

    var body: some View {
        if let tabView = context.tabView {
            tabView
                .environment(\.orbit, context)
                .environment(\.orbitContext, context)
        } else if let registration = context.owner?.registry.registration(for: route) {
            switch registration.navigation {
            case .stack:
                OrbitNavigationHost(context) { registration.factory(route) }
            case .content:
                registration.factory(route)
                    .environment(\.orbit, context)
                    .environment(\.orbitContext, context)
            }
        }
    }
}
