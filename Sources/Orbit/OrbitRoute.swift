import Foundation

/// A destination independent of its SwiftUI view.
/// Each instance is a distinct stack entry, even with identical payloads.
nonisolated open class OrbitRoute: Hashable, Identifiable {
    public final var id: ObjectIdentifier { ObjectIdentifier(self) }
    open class var routeName: String { String(describing: self) }
    public final var name: String { type(of: self).routeName }

    public init() {}

    public static func == (lhs: OrbitRoute, rhs: OrbitRoute) -> Bool {
        lhs === rhs
    }

    public final func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
