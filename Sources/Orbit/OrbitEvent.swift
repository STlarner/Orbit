import Foundation

/// Events contain names and identities only, never destination payloads.
public struct OrbitEvent: Sendable {
    public enum Kind: String, Sendable {
        case rootChanged, pathChanged, tabSelected
        case presented, dismissalRequested, dismissed, rejected
    }

    public let kind: Kind
    public let contextID: UUID?
    public let routeName: String?
    public let path: [String]
    public let message: String
}

/// Assertions are a development aid; rejection always emits an event and
/// leaves navigation state unchanged, including in release builds.
public enum OrbitDiagnostics: Sendable {
    case assertInDebug
    case eventsOnly
}

public enum OrbitPresentationStyle: Sendable {
    case sheet
    /// iOS full-screen cover. Rejected on macOS rather than silently adapted.
    case fullScreen
}

/// Used only when a route starts a root or modal flow. Pushed destinations
/// are never automatically wrapped in another NavigationStack.
public enum OrbitNavigationMode: Sendable {
    case stack
    case content
}
