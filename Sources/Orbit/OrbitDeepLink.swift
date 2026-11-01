import Foundation

/// Values captured from a deep-link path by a registered URL pattern.
///
/// Orbit creates these values while matching a path. Patterns use `:name` for
/// one captured segment, for example `"task/:id"` captures `id` from
/// `"task/42"`. Values are percent-decoded. This type is a plain value and does
/// not perform URL or scheme parsing.
public struct OrbitDeepLinkParameters: Sendable {
    /// Captured values keyed by parameter name.
    public let values: [String: String]

    /// Creates a parameter bag, normally from a matched deep link.
    /// - Parameter values: Captured values keyed by their pattern parameter.
    public init(_ values: [String: String] = [:]) {
        self.values = values
    }

    /// Returns the captured value for one pattern parameter.
    /// - Parameter name: Parameter name declared with `:name` in the pattern.
    /// - Returns: The decoded value, or `nil` when the parameter is absent.
    public subscript(_ name: String) -> String? { values[name] }
}

/// One normalized URL pattern and its captured segments.
struct OrbitDeepLinkPattern {
    private enum Segment {
        case literal(String)
        case parameter(String)
    }

    private let segments: [Segment]

    /// The normalized pattern used for duplicate detection and diagnostics.
    let source: String

    /// Creates a pattern from slash-separated literal and `:name` segments.
    /// - Parameter pattern: Pattern such as `"task/:id"`.
    init?(_ pattern: String) {
        let normalized = Self.normalize(pattern)
        guard !normalized.isEmpty else { return nil }

        var segments: [Segment] = []
        var names: Set<String> = []
        for raw in normalized.split(separator: "/") {
            let value = String(raw)
            if value.hasPrefix(":") {
                let name = String(value.dropFirst())
                guard !name.isEmpty, names.insert(name).inserted else {
                    return nil
                }
                segments.append(.parameter(name))
            } else {
                guard !value.contains(":") else { return nil }
                segments.append(.literal(value))
            }
        }

        guard !segments.isEmpty else { return nil }
        self.segments = segments
        self.source = normalized
    }

    /// Matches a normalized path and captures its parameter values.
    /// - Parameter path: Path such as `"task/42"` or `"/task/42/"`.
    /// - Returns: Captured values, or `nil` when the pattern does not match.
    func match(_ path: String) -> OrbitDeepLinkParameters? {
        let components = Self.normalize(path)
            .split(separator: "/")
            .map(String.init)
        guard components.count == segments.count else { return nil }

        var values: [String: String] = [:]
        for (segment, component) in zip(segments, components) {
            switch segment {
            case .literal(let literal):
                guard literal == component else { return nil }
            case .parameter(let name):
                values[name] = component.removingPercentEncoding ?? component
            }
        }
        return OrbitDeepLinkParameters(values)
    }

    private static func normalize(_ value: String) -> String {
        value.split(separator: "/", omittingEmptySubsequences: true)
            .joined(separator: "/")
    }
}

/// Stores URL-to-destination registrations for one scene owner.
@MainActor
final class DeepLinkRegistry {
    enum Destination {
        case route(
            tab: OrbitTab?,
            presentation: OrbitPresentationStyle?,
            resolve: @MainActor (OrbitDeepLinkParameters) async -> OrbitRoute?
        )
        case tab(OrbitTab)
    }

    struct Match {
        let parameters: OrbitDeepLinkParameters
        let destination: Destination
    }

    private struct Registration {
        let pattern: OrbitDeepLinkPattern
        let destination: Destination
    }

    private var registrations: [Registration] = []

    /// Stores one pattern unless an equivalent pattern already exists.
    /// - Returns: `true` when stored, `false` for a duplicate pattern.
    func register(
        pattern: OrbitDeepLinkPattern,
        destination: Destination
    ) -> Bool {
        guard !registrations.contains(where: {
            $0.pattern.source == pattern.source
        }) else {
            return false
        }
        registrations.append(Registration(
            pattern: pattern,
            destination: destination
        ))
        return true
    }

    /// Returns the first registration whose pattern matches the path.
    func match(_ path: String) -> Match? {
        for registration in registrations {
            guard let parameters = registration.pattern.match(path) else {
                continue
            }
            return Match(
                parameters: parameters,
                destination: registration.destination
            )
        }
        return nil
    }
}

extension Orbit {
    /// Registers a URL pattern that builds one already-registered route type.
    ///
    /// The route type must first be registered with
    /// ``Orbit/register(_:navigation:factory:)``. Registration stores the
    /// pattern and resolver without invoking them. Patterns are slash-separated;
    /// a segment beginning with `:` captures one path component. Matching is
    /// case-sensitive and the first registered match wins. Orbit does not parse
    /// schemes or hosts; pass a normalized path to ``resolveDeepLink(path:)`` or
    /// ``openDeepLink(path:)``.
    ///
    /// - Parameters:
    ///   - type: Exact route type to build. It must already be registered.
    ///   - pattern: Pattern such as `"task/:id"`.
    ///   - tab: Optional root tab selected when ``openDeepLink(path:)`` applies
    ///     the route. It is also the fallback when the resolver returns `nil`.
    ///     `nil` uses the current root tab or root stack.
    ///   - presentation: Optional modal style. `nil` pushes the route.
    ///   - resolve: Main-actor async closure that receives captured parameters
    ///     and returns the route, or `nil` when the destination is unavailable.
    /// - Returns: `true` when stored; `false` for an unregistered route, an
    ///   invalid pattern, a duplicate pattern or an unsupported style, subject
    ///   to the owner's diagnostics policy.
    @discardableResult
    public func registerDeepLink<R: OrbitRoute>(
        _ type: R.Type,
        pattern: String,
        tab: OrbitTab? = nil,
        presentation: OrbitPresentationStyle? = nil,
        resolve: @escaping @MainActor (OrbitDeepLinkParameters) async -> R?
    ) -> Bool {
        guard registry.isRegistered(type) else {
            return reject(
                "Cannot register a deep link for an unregistered route: \(type.routeName)"
            )
        }
        guard let pattern = OrbitDeepLinkPattern(pattern) else {
            return reject("Invalid deep-link pattern: \(pattern)")
        }
        #if os(macOS)
        if case .fullScreen? = presentation {
            return reject("Full-screen covers require iOS.")
        }
        #endif

        let resolveRoute: @MainActor (OrbitDeepLinkParameters) async -> OrbitRoute? = {
            await resolve($0)
        }
        guard deepLinks.register(
            pattern: pattern,
            destination: .route(
                tab: tab,
                presentation: presentation,
                resolve: resolveRoute
            )
        ) else {
            return reject("Deep-link pattern already registered: \(pattern.source)")
        }
        return true
    }

    /// Registers a path that selects a tab's root screen without pushing a
    /// route.
    ///
    /// Use this for destinations that are just a tab, such as `"home"` or
    /// `"tasks"`. Patterns follow the same slash, capture, normalization and
    /// first-match rules as
    /// ``registerDeepLink(_:pattern:tab:presentation:resolve:)``. A tab path and
    /// a route path cannot share the same normalized pattern.
    ///
    /// - Parameters:
    ///   - tab: Tab selected by ``openDeepLink(path:)``.
    ///   - pattern: Pattern such as `"home"`.
    /// - Returns: `true` when stored; `false` for an invalid or duplicate
    ///   pattern, subject to the owner's diagnostics policy.
    @discardableResult
    public func registerDeepLinkTab(
        _ tab: OrbitTab,
        pattern: String
    ) -> Bool {
        guard let pattern = OrbitDeepLinkPattern(pattern) else {
            return reject("Invalid deep-link pattern: \(pattern)")
        }
        guard deepLinks.register(
            pattern: pattern,
            destination: .tab(tab)
        ) else {
            return reject("Deep-link pattern already registered: \(pattern.source)")
        }
        return true
    }

    /// Resolves a route path without changing navigation.
    ///
    /// The first registered matching route pattern builds its route. Resolution
    /// may await application work such as loading an entity. Unknown paths,
    /// tab-only registrations and resolvers returning `nil` produce `nil`; this
    /// method does not emit a rejection for an ordinary unmatched URL.
    ///
    /// - Parameter path: Normalized path such as `"task/42"`.
    /// - Returns: The resolved registered route, or `nil`.
    @MainActor
    public func resolveDeepLink(path: String) async -> OrbitRoute? {
        guard let match = deepLinks.match(path) else { return nil }
        guard case .route(_, _, let resolve) = match.destination else {
            return nil
        }
        return await resolve(match.parameters)
    }

    /// Resolves a path and applies its registered tab and presentation policy.
    ///
    /// Captures the current root, resolves the destination, then verifies that
    /// the request was not cancelled and the root did not change. A tab-only
    /// registration selects its tab with an empty path. A route is pushed onto
    /// the registered tab (or the current root tab/stack); when its resolver
    /// returns `nil`, the registered tab's root is selected if a tab was
    /// provided, otherwise navigation is unchanged. A registered presentation
    /// is requested above the root; existing modals are not dismissed.
    /// Validation failure leaves navigation unchanged, except that a requested
    /// presentation is applied before selecting its tab in the same event batch.
    ///
    /// - Parameter path: Normalized path such as `"task/42"`.
    /// - Returns: `true` when navigation was applied; `false` for an unknown
    ///   path, an unavailable destination without a fallback tab, cancellation,
    ///   root replacement or a rejected command.
    @discardableResult
    @MainActor
    public func openDeepLink(path: String) async -> Bool {
        guard let root = rootRoute else { return false }
        guard let match = deepLinks.match(path) else { return false }

        switch match.destination {
        case .tab(let tab):
            guard !Task.isCancelled, rootRoute === root else { return false }
            return selectTab(tab, replacingPath: [])
        case .route(let tab, let presentation, let resolve):
            guard let route = await resolve(match.parameters) else {
                guard !Task.isCancelled, rootRoute === root, let tab else {
                    return false
                }
                return selectTab(tab, replacingPath: [])
            }
            guard !Task.isCancelled, rootRoute === root else { return false }
            guard registry.registration(for: route) != nil else {
                return reject(
                    "Deep link resolved to an unregistered route: \(route.name)"
                )
            }

            let targetTab = tab ?? rootContext.tabManager?.selectedTab
            if let targetTab {
                if let presentation {
                    guard let manager = rootContext.tabManager,
                        let context = manager.contexts[targetTab],
                        context.canSetPath([])
                    else {
                        return false
                    }
                    return mutate {
                        guard present(route, style: presentation) else {
                            return false
                        }
                        return selectTab(targetTab, replacingPath: [])
                    }
                }
                return selectTab(targetTab, replacingPath: [route])
            }
            if let presentation {
                return present(route, style: presentation)
            }
            return rootContext.push(route)
        }
    }
}
