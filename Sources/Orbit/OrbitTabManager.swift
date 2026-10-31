import Observation

@MainActor
@Observable
public final class OrbitTabManager {
    public let tabs: [OrbitTab]
    public private(set) var selectedTab: OrbitTab?

    @ObservationIgnored weak var owner: Orbit?
    @ObservationIgnored let contexts: [OrbitTab: OrbitContext]
    @ObservationIgnored let hadDuplicateTabs: Bool

    init(tabs: [OrbitTab]) {
        var unique: [OrbitTab] = []
        var contexts: [OrbitTab: OrbitContext] = [:]
        for tab in tabs where contexts[tab] == nil {
            unique.append(tab)
            contexts[tab] = OrbitContext(kind: .tab)
        }
        self.tabs = unique
        self.contexts = contexts
        self.selectedTab = unique.first
        self.hadDuplicateTabs = unique.count != tabs.count
    }

    public func context(for tab: OrbitTab) -> OrbitContext? {
        guard let context = contexts[tab] else {
            owner?.reject("Unknown tab: \(tab.name)")
            return nil
        }
        return context
    }

    /// Selects a tab, preserving its stack unless a replacement is provided.
    /// Pass [] to select its root screen. Invalid paths leave both the stack
    /// and selection unchanged. No timers or delayed pushes are scheduled.
    @discardableResult
    public func select(
        _ tab: OrbitTab,
        replacingPath path: [OrbitRoute]? = nil
    ) -> Bool {
        guard let context = context(for: tab) else { return false }
        if let path {
            guard context.canSetPath(path) else { return false }
            context.updatePath(path)
        }
        selectedTab = tabs.first(where: { $0 == tab })
        owner?.emit(.tabSelected, message: tab.name)
        return true
    }

    func reset() {
        for context in contexts.values { context.resetPath() }
        selectedTab = tabs.first
    }
}
