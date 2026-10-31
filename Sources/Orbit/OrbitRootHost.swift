import SwiftUI

/// Install once per scene, outside the root route and its optional tabs.
/// The placeholder receives the root router and can call setRoot itself.
@MainActor
public struct OrbitRootHost<Placeholder: View>: View {
    private let orbit: Orbit
    private let placeholder: () -> Placeholder

    public init(
        _ orbit: Orbit,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.orbit = orbit
        self.placeholder = placeholder
    }

    public var body: some View {
        Group {
            if let route = orbit.rootRoute {
                FlowContent(route: route, context: orbit.rootContext)
                    .id(route.id)
            } else {
                placeholder()
            }
        }
        .environment(\.orbit, orbit.rootContext)
        .environment(\.orbitTabs, orbit.tabs)
        // This modifier survives setRoot and does not belong to TabView.
        .modifier(PresentationModifier(context: orbit.rootContext))
    }
}

extension OrbitRootHost where Placeholder == EmptyView {
    public init(_ orbit: Orbit) {
        self.init(orbit) { EmptyView() }
    }
}
