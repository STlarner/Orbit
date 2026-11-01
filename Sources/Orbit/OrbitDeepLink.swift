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

/// Stores URL-to-route registrations for one scene owner.
@MainActor
final class DeepLinkRegistry {
    struct Match {
        let parameters: OrbitDeepLinkParameters
        let tab: OrbitTab?
        let presentation: OrbitPresentationStyle?
        let resolve: @MainActor (OrbitDeepLinkParameters) async -> OrbitRoute?
    }

    private struct Registration {
        let pattern: OrbitDeepLinkPattern
        let tab: OrbitTab?
        let presentation: OrbitPresentationStyle?
        let resolve: @MainActor (OrbitDeepLinkParameters) async -> OrbitRoute?
    }

    private var registrations: [Registration] = []

    /// Stores one pattern unless an equivalent pattern already exists.
    /// - Returns: `true` when stored, `false` for a duplicate pattern.
    func register(
        pattern: OrbitDeepLinkPattern,
        tab: OrbitTab?,
        presentation: OrbitPresentationStyle?,
        resolve: @escaping @MainActor (OrbitDeepLinkParameters) async -> OrbitRoute?
    ) -> Bool {
        guard !registrations.contains(where: {
            $0.pattern.source == pattern.source
        }) else {
            return false
        }
        registrations.append(Registration(
            pattern: pattern,
            tab: tab,
            presentation: presentation,
            resolve: resolve
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
                tab: registration.tab,
                presentation: registration.presentation,
                resolve: registration.resolve
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
    ///     the route. `nil` uses the current root tab or root stack.
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
            tab: tab,
            presentation: presentation,
            resolve: resolveRoute
        ) else {
            return reject("Deep-link pattern already registered: \(pattern.source)")
        }
        return true
    }

    /// Resolves a path without changing navigation.
    ///
    /// The first registered matching pattern builds its route. Resolution may
    /// await application work such as loading an entity. Unknown paths and
    /// resolvers returning `nil` produce `nil`; this method does not emit a
    /// rejection for an ordinary unmatched URL.
    ///
    /// - Parameter path: Normalized path such as `"task/42"`.
    /// - Returns: The resolved registered route, or `nil`.
    @MainActor
    public func resolveDeepLink(path: String) async -> OrbitRoute? {
        guard let match = deepLinks.match(path) else { return nil }
        return await match.resolve(match.parameters)
    }

    /// Resolves a path and applies its registered tab and presentation policy.
    ///
    /// Captures the current root, resolves the route, then verifies that the
    /// request was not cancelled and the root did not change. The route is
    /// pushed onto the registered tab (or the current root tab/stack). A
    /// registered presentation is requested above the root; existing modals are
    /// not dismissed. Validation failure leaves navigation unchanged, except
    /// that a requested presentation is applied before selecting its tab in the
    /// same event batch.
    ///
    /// - Parameter path: Normalized path such as `"task/42"`.
    /// - Returns: `true` when navigation was applied; `false` for an unknown
    ///   path, an unavailable destination, cancellation, root replacement or a
    ///   rejected command.
    @discardableResult
    @MainActor
    public func openDeepLink(path: String) async -> Bool {
        guard let root = rootRoute else { return false }
        guard let match = deepLinks.match(path) else { return false }
        guard let route = await match.resolve(match.parameters) else {
            return false
        }
        guard !Task.isCancelled, rootRoute === root else { return false }
        guard registry.registration(for: route) != nil else {
            return reject(
                "Deep link resolved to an unregistered route: \(route.name)"
            )
        }

        let targetTab = match.tab ?? rootContext.tabManager?.selectedTab
        if let targetTab {
            if let presentation = match.presentation {
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
        if let presentation = match.presentation {
            return present(route, style: presentation)
        }
        return rootContext.push(route)
    }
}
