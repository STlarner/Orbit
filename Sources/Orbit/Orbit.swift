import Observation
import SwiftUI

/// Stable owner for one scene. Create it before displaying the first route.
/// Orbit itself deliberately has no implicit push target.
@MainActor
@Observable
public final class Orbit {
    public private(set) var rootRoute: OrbitRoute?
    public let tabs: OrbitTabManager
    public let rootContext: OrbitContext

    @ObservationIgnored public var onEvent: (@MainActor (OrbitEvent) -> Void)?
    @ObservationIgnored private let diagnostics: OrbitDiagnostics
    @ObservationIgnored let registry = RouteRegistry()

    public init(
        tabs: [OrbitTab] = [],
        diagnostics: OrbitDiagnostics = .assertInDebug,
        onEvent: (@MainActor (OrbitEvent) -> Void)? = nil
    ) {
        self.diagnostics = diagnostics
        self.onEvent = onEvent
        self.tabs = OrbitTabManager(tabs: tabs)
        self.rootContext = OrbitContext(kind: .root)
        rootContext.owner = self
        self.tabs.owner = self
        for context in self.tabs.contexts.values {
            context.owner = self
        }
        if self.tabs.hadDuplicateTabs {
            reject("Duplicate tab types; only the first instance was kept.")
        }
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

    /// Replaces the root and resets root/tab stacks. Presented flows remain
    /// alive, allowing a modal to replace the root behind itself then dismiss.
    @discardableResult
    public func setRoot(_ route: OrbitRoute) -> Bool {
        guard validate(route) else { return false }
        rootContext.resetPath()
        tabs.reset()
        rootRoute = route
        emit(.rootChanged, context: rootContext, route: route)
        return true
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
        onEvent?(OrbitEvent(
            kind: kind,
            contextID: context?.id,
            routeName: route?.name,
            path: context?.path.map(\.name) ?? [],
            message: message
        ))
    }
}
