import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class OrbitContext: OrbitRouter, Identifiable {
    let id = UUID()
    private(set) var path: [OrbitRoute] = []

    enum Kind { case root, tab, modal }
    @ObservationIgnored let kind: Kind
    @ObservationIgnored weak var owner: Orbit?
    @ObservationIgnored weak var presenter: OrbitContext?
    @ObservationIgnored var presentationID: UUID?
    @ObservationIgnored weak var tabScope: OrbitContext?
    var presentation: PresentationState?
    private(set) var tabView: OrbitTabView?
    private(set) var tabContent: AnyView?
    private(set) var tabManager: OrbitTabManager?

    init(kind: Kind) { self.kind = kind }

    @discardableResult
    func setRoot(_ route: OrbitRoute) -> Bool {
        owner?.setRoot(route) ?? false
    }

    @discardableResult
    func push(_ route: OrbitRoute) -> Bool {
        setPath(path + [route])
    }

    func pop() {
        guard !path.isEmpty else { return }
        updatePath(Array(path.dropLast()))
    }

    func popToRoot() { resetPath() }

    func popTo(_ type: OrbitRoute.Type) {
        guard let index = path.lastIndex(where: {
            ObjectIdentifier(Swift.type(of: $0)) == ObjectIdentifier(type)
        }) else { return }
        updatePath(Array(path[...index]))
    }

    func popTo(_ route: OrbitRoute) {
        guard let index = path.lastIndex(of: route) else { return }
        updatePath(Array(path[...index]))
    }

    @discardableResult
    func selectTab(
        _ tab: OrbitTab,
        replacingPath path: [OrbitRoute]? = nil
    ) -> Bool {
        guard let manager = nearestTabManager else {
            return owner?.reject("This flow has no tab container.", context: self) ?? false
        }
        guard isActive else {
            return owner?.reject("The modal flow is closing.", context: self) ?? false
        }
        return manager.select(tab, replacingPath: path)
    }

    @discardableResult
    func present(
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
        let tabFlow = owner.registry.registration(for: route)?.tabsFactory?(route)
        guard owner.validateTabs(tabFlow?.declaration) else { return false }
        // Tabs delegate to their enclosing root/modal flow host. Each modal
        // hosts the next one; this hierarchy stays out of the public API.
        let start = kind == .tab ? (tabScope ?? owner.rootContext) : self
        guard let host = start.availablePresenter() else {
            return owner.reject("A presentation is closing.", context: self)
        }
        return owner.mutate {
            let child = OrbitContext(kind: .modal)
            child.owner = owner
            child.presenter = host
            child.tabScope = host.tabContainerScope ?? tabContainerScope
            child.installTabs(tabFlow)
            let state = PresentationState(route: route, style: style, context: child)
            child.presentationID = state.id
            host.presentation = state
            owner.emit(.presented, context: child, route: route)
            return true
        }
    }

    func dismiss() {
        if let presenter, let presentationID {
            presenter.requestDismiss(id: presentationID)
        } else if let presentation {
            requestDismiss(id: presentation.id)
        } else if kind == .tab {
            tabScope?.dismiss()
        }
    }

    @discardableResult
    func setPath(_ routes: [OrbitRoute]) -> Bool {
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
        return routes.allSatisfy { route in
            guard owner.validate(route) else { return false }
            guard owner.registry.registration(for: route)?.tabsFactory == nil else {
                return owner.reject(
                    "Tab flows cannot be pushed. Use setRoot or present.", context: self
                )
            }
            return true
        }
    }

    func updatePath(_ routes: [OrbitRoute]) {
        guard path != routes else { return }
        guard let owner else { return }
        owner.mutate {
            path = routes
            owner.emit(.pathChanged, context: self)
        }
    }

    func resetPath() { updatePath([]) }

    func installTabs(_ flow: PreparedTabFlow?) {
        clearTabs()
        tabView = flow?.declaration
        tabContent = flow?.content
        if let flow {
            tabManager = OrbitTabManager(tabs: flow.declaration.items.map(\.tab), flow: self)
        }
    }

    private var nearestTabManager: OrbitTabManager? {
        tabManager ?? tabScope?.nearestTabManager
    }

    private var tabContainerScope: OrbitContext? {
        tabManager != nil ? self : tabScope
    }

    private func clearTabs() {
        let previous = tabManager
        tabManager = nil
        tabView = nil
        tabContent = nil
        guard let previous else { return }
        for context in previous.contexts.values {
            invalidate(context)
        }
    }

    private func availablePresenter() -> OrbitContext? {
        guard let presentation else { return self }
        guard presentation.isPresented else { return nil }
        return presentation.context.availablePresenter()
    }

    private var isActive: Bool {
        if kind == .tab { return tabScope?.isActive ?? false }
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
        guard let owner else { return }
        owner.mutate {
            presentation.isPresented = false
            owner.emit(
                .dismissalRequested,
                context: presentation.context,
                route: presentation.route
            )
        }
    }

    func completeDismiss(id: UUID) {
        guard let presentation, presentation.id == id,
            !presentation.isPresented
        else { return }
        guard let owner else { return }
        owner.mutate {
            invalidate(presentation.context)
            self.presentation = nil
            owner.emit(
                .dismissed, context: presentation.context, route: presentation.route
            )
        }
    }

    private func invalidate(_ context: OrbitContext) {
        if let nested = context.presentation { invalidate(nested.context) }
        context.clearTabs()
        context.presentation = nil
        context.path = []
        context.presenter = nil
        context.owner = nil
        context.tabScope = nil
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
