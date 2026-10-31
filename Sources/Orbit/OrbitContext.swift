import Foundation
import Observation

@MainActor
@Observable
public final class OrbitContext: OrbitRouter, Identifiable {
    public let id = UUID()
    public private(set) var path: [OrbitRoute] = []

    enum Kind { case root, tab, modal }
    @ObservationIgnored let kind: Kind
    @ObservationIgnored weak var owner: Orbit?
    @ObservationIgnored weak var presenter: OrbitContext?
    @ObservationIgnored var presentationID: UUID?
    var presentation: PresentationState?

    init(kind: Kind) { self.kind = kind }

    @discardableResult
    public func setRoot(_ route: OrbitRoute) -> Bool {
        owner?.setRoot(route) ?? false
    }

    @discardableResult
    public func push(_ route: OrbitRoute) -> Bool {
        setPath(path + [route])
    }

    public func pop() {
        guard !path.isEmpty else { return }
        updatePath(Array(path.dropLast()))
    }

    public func popToRoot() { resetPath() }

    public func popTo(_ type: OrbitRoute.Type) {
        guard let index = path.lastIndex(where: {
            ObjectIdentifier(Swift.type(of: $0)) == ObjectIdentifier(type)
        }) else { return }
        updatePath(Array(path[...index]))
    }

    public func popTo(_ route: OrbitRoute) {
        guard let index = path.lastIndex(of: route) else { return }
        updatePath(Array(path[...index]))
    }

    @discardableResult
    public func selectTab(
        _ tab: OrbitTab,
        replacingPath path: [OrbitRoute]? = nil
    ) -> Bool {
        owner?.tabs.select(tab, replacingPath: path) ?? false
    }

    @discardableResult
    public func present(
        _ route: OrbitRoute,
        style: OrbitPresentationStyle
    ) -> Bool {
        guard let owner, owner.validate(route) else { return false }
        guard isActive else {
            return owner.reject("The modal flow is closing.", context: self)
        }
        #if os(macOS)
        guard style != .fullScreen else {
            return owner.reject("Full-screen covers require iOS.", context: self)
        }
        #endif
        // A tab is not a presentation owner. The scene hosts the first modal;
        // each modal hosts the next one. No public global/local distinction.
        let start = kind == .tab ? owner.rootContext : self
        guard let host = start.availablePresenter() else {
            return owner.reject("A presentation is closing.", context: self)
        }
        let child = OrbitContext(kind: .modal)
        child.owner = owner
        child.presenter = host
        let state = PresentationState(route: route, style: style, context: child)
        child.presentationID = state.id
        host.presentation = state
        owner.emit(.presented, context: child, route: route)
        return true
    }

    public func dismiss() {
        if let presenter, let presentationID {
            presenter.requestDismiss(id: presentationID)
        } else if let presentation {
            requestDismiss(id: presentation.id)
        } else if kind == .tab {
            owner?.rootContext.dismiss()
        }
    }

    @discardableResult
    public func setPath(_ routes: [OrbitRoute]) -> Bool {
        guard canSetPath(routes) else { return false }
        updatePath(routes)
        return true
    }

    func canSetPath(_ routes: [OrbitRoute]) -> Bool {
        guard let owner else { return false }
        guard routes.isEmpty || isActive else {
            return owner.reject("The modal flow is closing.", context: self)
        }
        if kind == .root, !routes.isEmpty {
            guard let root = owner.rootRoute,
                owner.registry.registration(for: root)?.navigation == .stack
            else {
                return owner.reject("The root does not host a stack.", context: self)
            }
        }
        if kind == .modal, !routes.isEmpty {
            guard let state = presenter?.presentation,
                state.id == presentationID,
                owner.registry.registration(for: state.route)?.navigation == .stack
            else {
                return owner.reject("The modal does not host a stack.", context: self)
            }
        }
        guard Set(routes).count == routes.count else {
            return owner.reject("A route instance occurs twice in a stack.", context: self)
        }
        return routes.allSatisfy { owner.validate($0) }
    }

    func updatePath(_ routes: [OrbitRoute]) {
        guard path != routes else { return }
        path = routes
        owner?.emit(.pathChanged, context: self)
    }

    func resetPath() { updatePath([]) }

    private func availablePresenter() -> OrbitContext? {
        guard let presentation else { return self }
        guard presentation.isPresented else { return nil }
        return presentation.context.availablePresenter()
    }

    private var isActive: Bool {
        guard kind == .modal else { return true }
        guard let presenter, let state = presenter.presentation,
            state.id == presentationID, state.isPresented
        else { return false }
        return presenter.isActive
    }

    func requestDismiss(id: UUID) {
        guard let presentation, presentation.id == id,
            presentation.isPresented
        else { return }
        presentation.isPresented = false
        owner?.emit(
            .dismissalRequested,
            context: presentation.context,
            route: presentation.route
        )
    }

    func completeDismiss(id: UUID) {
        guard let presentation, presentation.id == id,
            !presentation.isPresented
        else { return }
        invalidate(presentation.context)
        self.presentation = nil
        // Consumers may immediately present again from the completion event.
        owner?.emit(
            .dismissed, context: presentation.context, route: presentation.route
        )
    }

    private func invalidate(_ context: OrbitContext) {
        if let nested = context.presentation { invalidate(nested.context) }
        context.presentation = nil
        context.path = []
        context.presenter = nil
        context.owner = nil
    }
}

@MainActor
@Observable
final class PresentationState: Identifiable {
    let id = UUID()
    let route: OrbitRoute
    let style: OrbitPresentationStyle
    let context: OrbitContext
    var isPresented = true

    init(
        route: OrbitRoute,
        style: OrbitPresentationStyle,
        context: OrbitContext
    ) {
        self.route = route
        self.style = style
        self.context = context
    }
}
