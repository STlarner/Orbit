/// A tab key identified by its concrete Swift type, not by its instance or label.
///
/// Declare one subclass per tab, then use instances in ``OrbitTabItem`` and
/// `selectTab` calls. Instances of the same subclass are interchangeable; two
/// different subclasses remain distinct even with the same diagnostic name.
/// A flow cannot declare the same subclass twice. Labels belong to tab items.
nonisolated open class OrbitTab: Hashable {
    /// Diagnostic label, defaulting to the concrete Swift type name.
    /// Override for readable logs; it does not affect identity or selection.
    open class var tabName: String { String(describing: self) }

    /// The concrete type's diagnostic ``tabName``.
    public final var name: String { type(of: self).tabName }

    /// Creates a tab key. Another instance of the same concrete type compares equal.
    public init() {}

    /// Compares exact concrete Swift types, ignoring instance identity and names.
    /// - Parameters:
    ///   - lhs: First tab key.
    ///   - rhs: Second tab key.
    /// - Returns: `true` if both have the same concrete Swift type.
    public static func == (lhs: OrbitTab, rhs: OrbitTab) -> Bool {
        ObjectIdentifier(type(of: lhs)) == ObjectIdentifier(type(of: rhs))
    }

    /// Hashes the concrete type, consistently with type-based equality.
    /// - Parameter hasher: Hasher receiving the concrete type's identifier.
    public final func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(type(of: self)))
    }
}
