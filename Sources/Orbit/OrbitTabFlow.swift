import SwiftUI

/// A view that preserves the declaration of one independent tab flow.
///
/// ``OrbitTabView`` conforms automatically, as do chains of SwiftUI
/// `ModifiedContent` whose content preserves a tab flow. Orbit reads this
/// public metadata rather than reflecting into private SwiftUI view storage.
/// Custom wrappers may conform by returning the same declaration they render,
/// or use ``wrapped(content:)`` without implementing a conformance.
@MainActor
public protocol OrbitTabFlow: View {
    /// The declaration rendered by this flow, preserving its original identity.
    /// Return the same stored value on each access; do not construct a new
    /// OrbitTabView in this getter or render multiple copies of the declaration.
    var orbitTabView: OrbitTabView { get }
}

extension OrbitTabFlow {
    /// Decorates a tab flow while preserving metadata through any view wrapper.
    ///
    /// Ordinary ModifiedContent modifiers preserve metadata automatically.
    /// Use this for Group, AnyView, custom containers, or transformations that
    /// do not return ModifiedContent. For example:
    ///
    /// ```swift
    /// nonisolated final class HomeTab: OrbitTab {}
    ///
    /// @MainActor
    /// func makeWrappedTabs() -> some View {
    ///     OrbitTabView {
    ///         OrbitTabItem(HomeTab()) { Text("Home") } label: { Text("Home") }
    ///     }
    ///     .wrapped { tabs in AnyView(tabs.padding()) }
    /// }
    /// ```
    ///
    /// - Parameter content: Builds the decorated view from this flow. Include
    ///   the supplied flow exactly once. Evaluated when the registration factory
    ///   prepares a root/modal, without evaluating SwiftUI `body` or tab content.
    /// - Returns: A registered-flow-compatible wrapper retaining both the
    ///   original tab declaration and the complete decorated view.
    public func wrapped<Content: View>(
        @ViewBuilder content: (Self) -> Content
    ) -> OrbitWrappedTabFlow<Content> {
        OrbitWrappedTabFlow(self, content: content)
    }
}

/// Preserves one tab declaration alongside arbitrary decorated SwiftUI content.
///
/// Usually created with ``OrbitTabFlow/wrapped(content:)``. Native modifiers
/// can be applied to this wrapper too, without losing its flow metadata.
@MainActor
public struct OrbitWrappedTabFlow<Content: View>: OrbitTabFlow {
    /// The original tab declaration; its identity is not changed by decoration.
    public let orbitTabView: OrbitTabView
    private let content: Content

    /// Creates a wrapper for one tab flow without reading its SwiftUI body.
    /// - Parameters:
    ///   - flow: Source flow whose declaration must be preserved.
    ///   - content: Decorates that source. Render the supplied flow exactly once.
    public init<Flow: OrbitTabFlow>(
        _ flow: Flow,
        @ViewBuilder content: (Flow) -> Content
    ) {
        self.orbitTabView = flow.orbitTabView
        self.content = content(flow)
    }

    /// The complete decorated view, not an undecorated replacement of the tabs.
    public var body: some View { content }
}

/// Preserves tab-flow metadata through native SwiftUI ModifiedContent chains.
extension ModifiedContent: OrbitTabFlow
where Content: OrbitTabFlow, Modifier: ViewModifier {
    /// The original tab declaration supplied by the modified content.
    @MainActor
    public var orbitTabView: OrbitTabView { content.orbitTabView }
}

/// A prepared tab flow retains both its declaration and its decorated rendering.
@MainActor
struct PreparedTabFlow {
    let declaration: OrbitTabView
    let content: AnyView

    init<Flow: OrbitTabFlow>(_ flow: Flow) {
        declaration = flow.orbitTabView
        content = AnyView(flow)
    }
}
