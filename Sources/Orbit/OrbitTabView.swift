import Foundation
import SwiftUI

/// A tab declaration. Content and label factories remain lazy: declaring a
/// flow does not instantiate its screens or their dependencies.
@MainActor
public struct OrbitTabItem {
    let tab: OrbitTab
    let makeContent: () -> AnyView
    let makeLabel: () -> AnyView

    public init<Content: View, Label: View>(
        _ tab: OrbitTab,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.tab = tab
        self.makeContent = { AnyView(content()) }
        self.makeLabel = { AnyView(label()) }
    }
}

@MainActor
@resultBuilder
public enum OrbitTabBuilder {
    public static func buildExpression(_ item: OrbitTabItem) -> [OrbitTabItem] {
        [item]
    }

    public static func buildBlock(_ components: [OrbitTabItem]...) -> [OrbitTabItem] {
        components.flatMap { $0 }
    }

    public static func buildOptional(_ component: [OrbitTabItem]?) -> [OrbitTabItem] {
        component ?? []
    }

    public static func buildEither(first: [OrbitTabItem]) -> [OrbitTabItem] { first }
    public static func buildEither(second: [OrbitTabItem]) -> [OrbitTabItem] { second }
    public static func buildArray(_ components: [[OrbitTabItem]]) -> [OrbitTabItem] {
        components.flatMap { $0 }
    }
}

/// Optional iOS tab-bar policy. Orbit preserves SwiftUI's default unless the
/// app explicitly chooses otherwise; it never changes push semantics.
public enum OrbitTabBarVisibility: Sendable {
    case automatic
    case visible
    case hiddenOnPush
}

/// Declare tab content here; Orbit owns selection, tags, bindings and one
/// independent stack per tab. `register` recognizes this return type.
@MainActor
public struct OrbitTabView: View {
    @Environment(\.orbitContext) private var context
    let id = UUID()
    let items: [OrbitTabItem]
    private let tabBarVisibility: OrbitTabBarVisibility

    public init(
        tabBarVisibility: OrbitTabBarVisibility = .automatic,
        @OrbitTabBuilder content: () -> [OrbitTabItem]
    ) {
        self.items = content()
        self.tabBarVisibility = tabBarVisibility
    }

    public var body: some View {
        if let context, context.tabView?.id == id,
            let manager = context.tabManager
        {
            TabView(selection: Binding(
                get: { manager.selectedTab },
                set: { if let tab = $0 { manager.select(tab) } }
            )) {
                ForEach(items, id: \.tab) { item in
                    if let stack = manager.contexts[item.tab] {
                        OrbitNavigationHost(stack) { item.makeContent() }
                            .modifier(TabBarModifier(
                                policy: tabBarVisibility, context: stack
                            ))
                            .tabItem { item.makeLabel() }
                            .tag(item.tab as OrbitTab?)
                    }
                }
            }
        } else {
            Color.clear.onAppear {
                context?.owner?.reject(
                    "Return OrbitTabView directly from Orbit.register(_:factory:)."
                )
            }
        }
    }
}

@MainActor
private struct TabBarModifier: ViewModifier {
    let policy: OrbitTabBarVisibility
    let context: OrbitContext

    func body(content: Content) -> some View {
        #if os(iOS)
        content.toolbar(visibility, for: .tabBar)
        #else
        content
        #endif
    }

    private var visibility: Visibility {
        switch policy {
        case .automatic: .automatic
        case .visible: .visible
        case .hiddenOnPush: context.path.isEmpty ? .automatic : .hidden
        }
    }
}
