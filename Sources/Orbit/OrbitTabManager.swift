import Observation

@MainActor
@Observable
final class OrbitTabManager {
    let tabs: [OrbitTab]
    private(set) var selectedTab: OrbitTab?

    @ObservationIgnored weak var flow: OrbitContext?
    @ObservationIgnored let contexts: [OrbitTab: OrbitContext]

    init(tabs: [OrbitTab], flow: OrbitContext) {
        var unique: [OrbitTab] = []
        var contexts: [OrbitTab: OrbitContext] = [:]
        for tab in tabs where contexts[tab] == nil {
            unique.append(tab)
            let context = OrbitContext(kind: .tab)
            context.owner = flow.owner
            context.tabScope = flow
            contexts[tab] = context
        }
        self.tabs = unique
        self.contexts = contexts
        self.selectedTab = unique.first
        self.flow = flow
    }

    func context(for tab: OrbitTab) -> OrbitContext? {
        guard let context = contexts[tab] else {
            flow?.owner?.reject("Unknown tab: \(tab.name)")
            return nil
        }
        return context
    }

    /// Selects a tab, preserving its stack unless a replacement is provided.
    /// Pass [] to select its root screen. Invalid paths leave both the stack
    /// and selection unchanged. No timers or delayed pushes are scheduled.
    @discardableResult
    func select(
        _ tab: OrbitTab,
        replacingPath path: [OrbitRoute]? = nil
    ) -> Bool {
        guard let context = context(for: tab), context.owner != nil else { return false }
        if let path {
            guard context.canSetPath(path) else { return false }
            context.updatePath(path)
        }
        selectedTab = tabs.first(where: { $0 == tab })
        flow?.owner?.emit(.tabSelected, context: flow, message: tab.name)
        return true
    }

}
