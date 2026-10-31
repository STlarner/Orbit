@MainActor
public protocol OrbitRouter: AnyObject {
    @discardableResult func setRoot(_ route: OrbitRoute) -> Bool
    @discardableResult func push(_ route: OrbitRoute) -> Bool
    func pop()
    func popToRoot()
    func popTo(_ type: OrbitRoute.Type)
    func popTo(_ route: OrbitRoute)
    @discardableResult func selectTab(_ tab: OrbitTab) -> Bool
    @discardableResult func present(
        _ route: OrbitRoute,
        style: OrbitPresentationStyle
    ) -> Bool
    func dismiss()
}

extension OrbitRouter {
    @discardableResult
    public func present(_ route: OrbitRoute) -> Bool {
        present(route, style: .sheet)
    }
}
