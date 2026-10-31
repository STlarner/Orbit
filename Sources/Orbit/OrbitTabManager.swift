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

    @discardableResult
    public func select(_ tab: OrbitTab) -> Bool {
        guard contexts[tab] != nil else {
            return owner?.reject("Unknown tab: \(tab.name)") ?? false
        }
        selectedTab = tabs.first(where: { $0 == tab })
        owner?.emit(.tabSelected, message: tab.name)
        return true
    }

    /// Updates the target stack and selection synchronously, with no timers.
    /// URL parsing, async data resolution and modal dismissal remain app policy.
    @discardableResult
    public func navigate(to tab: OrbitTab, path: [OrbitRoute]) -> Bool {
        guard let context = context(for: tab), context.canSetPath(path) else {
            return false
        }
        context.updatePath(path)
        return select(tab)
    }

    func reset() {
        for context in contexts.values { context.resetPath() }
        selectedTab = tabs.first
    }
}
