import SwiftUI

/// Displays a scene's current root and owns its SwiftUI presentation lifecycle.
///
/// Install one host for each independent ``Orbit`` owner, outside root/tab
/// content. The host injects an ``OrbitRouter`` and renders ordinary root flows
/// with their configured stack or recognized tab flows with independent stacks.
/// Its presentation host survives root replacements. Do not share one owner
/// between windows or install multiple active hosts for it.
@MainActor
public struct OrbitRootHost<Placeholder: View>: View {
    private let orbit: Orbit
    private let placeholder: () -> Placeholder

    /// Creates a host with content displayed before the first root is selected.
    ///
    /// The placeholder receives the root router and may resolve a launch
    /// destination asynchronously, then call `setRoot`. It is not automatically
    /// wrapped in a NavigationStack; no pushed path exists before a root is set.
    /// - Parameters:
    ///   - orbit: Scene-specific owner, retained by this host.
    ///   - placeholder: SwiftUI content used while `rootRoute` is `nil`. SwiftUI
    ///     may evaluate it repeatedly; keep one-shot work in a cancellable `.task`.
    public init(
        _ orbit: Orbit,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.orbit = orbit
        self.placeholder = placeholder
    }

    /// The root or placeholder with environment routing and modal presentation hosts.
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
        .environment(\.orbitContext, orbit.rootContext)
        // This modifier survives setRoot and does not belong to TabView.
        .modifier(PresentationModifier(context: orbit.rootContext))
    }
}

extension OrbitRootHost where Placeholder == EmptyView {
    /// Creates a host whose initial placeholder is EmptyView.
    /// - Parameter orbit: Scene-specific owner. Set its root before displaying
    ///   this host, or from an external launch coordinator afterward.
    public init(_ orbit: Orbit) {
        self.init(orbit) { EmptyView() }
    }
}
