/// A tab identified by its concrete Swift type, not a display name.
nonisolated open class OrbitTab: Hashable {
    open class var tabName: String { String(describing: self) }
    public final var name: String { type(of: self).tabName }

    public init() {}

    public static func == (lhs: OrbitTab, rhs: OrbitTab) -> Bool {
        ObjectIdentifier(type(of: lhs)) == ObjectIdentifier(type(of: rhs))
    }

    public final func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(type(of: self)))
    }
}
