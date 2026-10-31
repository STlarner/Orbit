import Observation
import SwiftUI

/// Stable owner for one scene. Create it before displaying the first route.
/// Orbit itself deliberately has no implicit push target.
@MainActor
@Observable
public final class Orbit {
    public private(set) var rootRoute: OrbitRoute?
    let rootContext: OrbitContext

    /// Observes navigation state changes and rejected commands. This is not
    /// an interceptor and cannot approve or block a navigation operation.
    @ObservationIgnored public var onNavigationEvent: (@MainActor (OrbitEvent) -> Void)?
    @ObservationIgnored private let diagnostics: OrbitDiagnostics
    @ObservationIgnored let registry = RouteRegistry()

    public init(
        diagnostics: OrbitDiagnostics = .assertInDebug
    ) {
        self.diagnostics = diagnostics
        self.rootContext = OrbitContext(kind: .root)
        rootContext.owner = self
    }

    @discardableResult
    public func register<R: OrbitRoute, V: View>(
        _ type: R.Type,
        navigation: OrbitNavigationMode = .stack,
        @ViewBuilder factory: @escaping @MainActor (R) -> V
    ) -> Bool {
        guard registry.register(
            type, navigation: navigation, factory: factory
        ) else {
            return reject("Route type already registered: \(type.routeName)")
        }
        return true
    }

    /// Registers a complete tab flow, usable as a root or a modal. The tab
    /// declaration is prepared before navigation is published; screen content
    /// remains lazy. No manual contexts, hosts, bindings or tags are required.
    @discardableResult
    public func register<R: OrbitRoute>(
        _ type: R.Type,
        @ViewBuilder factory: @escaping @MainActor (R) -> OrbitTabView
    ) -> Bool {
        guard registry.registerTabs(type, factory: factory) else {
            return reject("Route type already registered: \(type.routeName)")
        }
        return true
    }

    /// Replaces the root and resets root/tab stacks. Presented flows remain
    /// alive, allowing a modal to replace the root behind itself then dismiss.
    @discardableResult
    public func setRoot(_ route: OrbitRoute) -> Bool {
        guard validate(route) else { return false }
        let tabView = registry.registration(for: route)?.tabsFactory?(route)
        guard validateTabs(tabView) else { return false }
        rootContext.resetPath()
        rootContext.installTabs(tabView)
        rootRoute = route
        emit(.rootChanged, context: rootContext, route: route)
        return true
    }

    /// Selects a tab in the current root flow. Screens use their environment
    /// router to target their nearest tab container (including modal tabs).
    @discardableResult
    public func selectTab(
        _ tab: OrbitTab,
        replacingPath path: [OrbitRoute]? = nil
    ) -> Bool {
        rootContext.selectTab(tab, replacingPath: path)
    }

    @discardableResult
    public func present(
        _ route: OrbitRoute,
        style: OrbitPresentationStyle = .sheet
    ) -> Bool {
        rootContext.present(route, style: style)
    }

    /// Explicitly closes the complete modal chain, independently of style.
    public func dismissAll() {
        if let presentation = rootContext.presentation {
            rootContext.requestDismiss(id: presentation.id)
        }
    }

    func validate(_ route: OrbitRoute) -> Bool {
        guard registry.registration(for: route) != nil else {
            return reject("Unregistered route: \(route.name)")
        }
        return true
    }

    func validateTabs(_ view: OrbitTabView?) -> Bool {
        guard let view else { return true }
        guard !view.items.isEmpty else {
            return reject("A tab flow must declare at least one tab.")
        }
        guard Set(view.items.map(\.tab)).count == view.items.count else {
            return reject("A tab flow declares the same tab type more than once.")
        }
        return true
    }

    @discardableResult
    func reject(_ message: String, context: OrbitContext? = nil) -> Bool {
        emit(.rejected, context: context, message: message)
        if diagnostics == .assertInDebug {
            assertionFailure(message)
        }
        return false
    }

    func emit(
        _ kind: OrbitEvent.Kind,
        context: OrbitContext? = nil,
        route: OrbitRoute? = nil,
        message: String = ""
    ) {
        onNavigationEvent?(OrbitEvent(
            kind: kind,
            contextID: context?.id,
            routeName: route?.name,
            path: context?.path.map(\.name) ?? [],
            message: message
        ))
    }
}
