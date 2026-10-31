import Foundation

/// A destination's identity and payload, independent of its SwiftUI view.
///
/// Subclass this type, store the arguments required by the destination, and
/// register a factory for the exact subclass. Equality uses reference identity,
/// so two instances with identical payloads are different destinations. Prefer
/// immutable payloads. This type is nonisolated, but is not implicitly Sendable
/// or Codable; callers own cross-actor payload safety and state restoration.
nonisolated open class OrbitRoute: Hashable, Identifiable {
    /// Identity of this live instance, used for hashing and root view identity.
    /// Not persistent, serializable or stable across process launches.
    public final var id: ObjectIdentifier { ObjectIdentifier(self) }

    /// Diagnostic label for this route type, defaulting to its Swift type name.
    /// Override for readable logs; it never determines registration or equality.
    open class var routeName: String { String(describing: self) }

    /// The concrete type's diagnostic ``routeName`` for this instance.
    public final var name: String { type(of: self).routeName }

    /// Creates a distinct route identity. Subclass initializers call `super.init()`.
    public init() {}

    /// Returns whether both references point to the same route instance.
    /// - Parameters:
    ///   - lhs: First route reference.
    ///   - rhs: Second route reference.
    /// - Returns: `true` only for identical references, regardless of payloads.
    public static func == (lhs: OrbitRoute, rhs: OrbitRoute) -> Bool {
        lhs === rhs
    }

    /// Hashes live-instance identity, consistently with reference equality.
    /// - Parameter hasher: Hasher receiving this instance's object identifier.
    public final func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
