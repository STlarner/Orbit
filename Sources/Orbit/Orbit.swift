import Observation
import SwiftUI

/// Owns route registration, root navigation and presentations for one scene.
///
/// Keep one instance alive for each independent window and install it in an
/// ``OrbitRootHost``. Screens receive an ``OrbitRouter`` through the SwiftUI
/// environment; this owner deliberately has no implicit push target.
/// All commands and factories run on the main actor. A successful command
/// updates navigation state, notifies observers and lets SwiftUI render later;
/// it does not acknowledge that a transition has finished.
@MainActor
@Observable
public final class Orbit {
    /// The registered route currently displayed by the root host.
    ///
    /// Initially `nil`; the host displays its placeholder until ``setRoot(_:)``
    /// succeeds. Read this observable property to react to root changes. The
    /// root cannot be assigned or cleared directly.
    public private(set) var rootRoute: OrbitRoute?
    let rootContext: OrbitContext

    /// An optional synchronous observer for state changes and rejected commands.
    ///
    /// Receives ``OrbitEvent`` on the main actor. Assign `nil` to stop observing.
    /// This is not an interceptor and cannot approve or block a command. Events
    /// describe model updates, not completed UI transitions; `.presented` means
    /// a presentation request was accepted.
    ///
    /// Keep the callback short and capture this owner weakly when necessary to
    /// avoid a retain cycle. A command completes all its state changes before
    /// delivering its event batch. Callbacks may issue further commands; their
    /// events are delivered after the current batch, without recursive callback
    /// calls. Events are immutable operation snapshots, not a guarantee that
    /// live state still matches after another callback changes it. Avoid
    /// unbounded feedback loops when reacting to your own generated events.
    @ObservationIgnored public var onNavigationEvent: (@MainActor (OrbitEvent) -> Void)?
    @ObservationIgnored private let diagnostics: OrbitDiagnostics
    @ObservationIgnored let registry = RouteRegistry()
    @ObservationIgnored let deepLinks = DeepLinkRegistry()
    @ObservationIgnored private var isMutating = false
    @ObservationIgnored private var isDeliveringEvents = false
    @ObservationIgnored private var pendingEvents: [OrbitEvent] = []

    /// Creates an owner with an empty registry, no root and no declared tabs.
    ///
    /// - Parameter diagnostics: Validation policy. The default asserts in
    ///   debug builds and rejects invalid requests without mutation in release.
    ///   Use `.eventsOnly` to receive rejection events without assertions.
    public init(
        diagnostics: OrbitDiagnostics = .assertInDebug
    ) {
        self.diagnostics = diagnostics
        self.rootContext = OrbitContext(kind: .root)
        rootContext.owner = self
    }

    /// Registers a SwiftUI factory for one exact route type.
    ///
    /// Registration stores the closure without invoking it. For ordinary views,
    /// SwiftUI may call the factory repeatedly during rendering; keep it free
    /// of one-shot side effects. Results conforming to ``OrbitTabFlow`` are
    /// recognized as tab flows, including OrbitTabView and native SwiftUI
    /// ModifiedContent modifier chains. Use `wrapped` for Group, AnyView or
    /// arbitrary transformations that erase flow metadata. Custom wrappers can
    /// conform to OrbitTabFlow. No private view hierarchy is inspected.
    ///
    /// - Parameters:
    ///   - type: Exact type to register. Subclasses need their own registration;
    ///     diagnostic route names are not registry keys.
    ///   - navigation: How an ordinary root or modal starts its flow. Defaults
    ///     to `.stack`; pushed destinations are never wrapped in another stack.
    ///     This option is ignored for a recognized tab flow.
    ///   - factory: Main-actor closure that receives the route's payload and
    ///     constructs its destination. Retained until this owner is released.
    /// - Returns: `true` when stored, or `false` for an already registered type,
    ///   subject to the owner's diagnostics policy. Existing factories remain.
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

    /// Displays a registered root and retires the previous root's stack and tabs.
    ///
    /// Tab declarations are validated and prepared before the root is published;
    /// a new tab flow starts with its first declared tab selected. Presented
    /// flows remain alive, so onboarding can replace the root behind itself and
    /// then dismiss. An independent modal tab flow retains its selection/path.
    ///
    /// Use a fresh route instance to restart the root's SwiftUI view identity.
    /// Reusing an instance clears navigation paths but keeps the same root ID
    /// and may preserve view-local SwiftUI state.
    ///
    /// - Parameter route: The new root, already registered under its exact type.
    /// - Returns: `true` if accepted; `false` for an unregistered route or an
    ///   empty/duplicate tab declaration, subject to diagnostics. Validation
    ///   failure leaves the current root and modal state unchanged.
    @discardableResult
    public func setRoot(_ route: OrbitRoute) -> Bool {
        guard validate(route) else { return false }
        let tabFlow = registry.registration(for: route)?.tabsFactory?(route)
        guard validateTabs(tabFlow?.declaration) else { return false }
        return mutate {
            rootContext.resetPath()
            rootContext.installTabs(tabFlow)
            rootRoute = route
            emit(.rootChanged, context: rootContext, route: route)
            return true
        }
    }

    /// Selects a tab belonging to the current root flow.
    ///
    /// Unlike the environment router, this owner always targets the root's tab
    /// container, not a modal's tabs. Useful for resolved deep-link destinations:
    /// root tabs are ready after `setRoot`, before their screens are rendered.
    /// This does not dismiss active modals or change any other tab's stack.
    ///
    /// - Parameters:
    ///   - tab: A declared tab, identified by exact Swift type.
    ///   - path: `nil` (the default) preserves its stack. An array replaces the
    ///     entire stack; `[]` selects its root screen. Entries must be registered,
    ///     distinct route instances and cannot be independent tab flows.
    /// - Returns: `true` if accepted; `false` if there is no root tab container,
    ///   the tab is unknown or the replacement is invalid, subject to diagnostics.
    ///   Validation failure changes neither selection nor path.
    @discardableResult
    public func selectTab(
        _ tab: OrbitTab,
        replacingPath path: [OrbitRoute]? = nil
    ) -> Bool {
        rootContext.selectTab(tab, replacingPath: path)
    }

    /// Requests a modal above the root's active presentation chain.
    ///
    /// The first modal is hosted outside the root's tab container. Further
    /// requests are hosted by the topmost model presentation. Each modal gets
    /// an independent stack or tab flow; tab declarations are validated before
    /// acceptance. This is a state request, not a presentation-completion API.
    ///
    /// - Parameters:
    ///   - route: Registered destination to present. Independent tab flows are
    ///     allowed here, unlike in a pushed path.
    ///   - style: `.sheet` by default; `.fullScreen` is supported only on iOS.
    /// - Returns: `true` if accepted; `false` for failed validation, an unsupported
    ///   style or a closing target chain, subject to diagnostics. No request is
    ///   queued and no arbitrary delay is scheduled.
    @discardableResult
    public func present(
        _ route: OrbitRoute,
        style: OrbitPresentationStyle = .sheet
    ) -> Bool {
        rootContext.present(route, style: style)
    }

    /// Requests dismissal of the complete modal chain, regardless of styles.
    ///
    /// Leaves the root and root-tab paths unchanged. Does nothing when no modal
    /// exists. Cleanup completes through SwiftUI's dismissal callback, not before
    /// this method returns. Descendant contexts are invalidated with their parent;
    /// they do not each emit a separate completed-dismissal event.
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
        pendingEvents.append(OrbitEvent(
            kind: kind,
            contextID: context?.id,
            routeName: route?.name,
            path: context?.path.map(\.name) ?? [],
            message: message
        ))
        if !isMutating { deliverEvents() }
    }

    /// Keeps multi-step state changes ahead of their observer notifications.
    /// Nested internal updates join the same batch, without an async scheduler.
    @discardableResult
    func mutate<Value>(_ mutation: () -> Value) -> Value {
        if isMutating { return mutation() }
        isMutating = true
        let result = mutation()
        isMutating = false
        deliverEvents()
        return result
    }

    /// Reentrant commands complete their own mutations immediately. Their
    /// snapshots are appended after the current event batch instead of causing
    /// recursive observer calls or resuming an unfinished state update.
    private func deliverEvents() {
        guard !isDeliveringEvents else { return }
        isDeliveringEvents = true
        while !pendingEvents.isEmpty {
            let batch = pendingEvents
            pendingEvents.removeAll(keepingCapacity: true)
            for event in batch { onNavigationEvent?(event) }
        }
        isDeliveringEvents = false
    }
}
