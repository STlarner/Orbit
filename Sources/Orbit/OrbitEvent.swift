import Foundation

/// A read-only snapshot emitted through ``Orbit/onNavigationEvent``.
///
/// Contains diagnostic names and identifiers, not route payloads. This Sendable
/// value can be forwarded to logging infrastructure. It is created by Orbit;
/// there is no public memberwise initializer. Events describe model operations,
/// not UIKit/SwiftUI transition completion except for dismissal cleanup. A
/// command's state updates complete before its FIFO event batch is delivered.
/// Reentrant command events are queued after that batch, not recursively called.
public struct OrbitEvent: Sendable {
    /// The operation represented by an event. Raw string values match case names.
    public enum Kind: String, Sendable {
        /// An accepted root replacement, after the new flow's state is prepared.
        case rootChanged
        /// A changed pushed path, including SwiftUI back-navigation updates.
        case pathChanged
        /// An accepted tab-selection request, including selecting the same tab.
        case tabSelected
        /// An accepted modal request; the modal may not yet be rendered or visible.
        case presented
        /// A requested modal close; cleanup has not yet completed.
        case dismissalRequested
        /// SwiftUI dismissal cleanup completed for the explicitly closed flow.
        /// Descendants invalidated with it do not each emit another event.
        case dismissed
        /// Invalid configuration or a command rejected by validation.
        case rejected
    }

    /// Operation category; determines which other fields are meaningful.
    public let kind: Kind

    /// Opaque identifier of the involved internal stack/flow, when available.
    /// It is diagnostic-only, not a route ID, tab key or persistent identifier.
    public let contextID: UUID?

    /// Destination's diagnostic name for root and presentation events.
    /// Usually `nil` for path, selection and rejection events.
    public let routeName: String?

    /// Diagnostic route names in the involved context's current pushed path.
    /// Excludes the root; tab-selection events refer to the containing flow,
    /// not the selected tab's path. Completed dismissal has an empty path.
    public let path: [String]

    /// Diagnostic detail, such as a selected tab name or rejection reason.
    /// Often empty for successful root/path/presentation operations. Not a
    /// localized user-facing string or a stable error-code contract.
    public let message: String
}

/// Validation policy for an ``Orbit`` instance.
///
/// Reported validation failures record `.rejected` before a development assertion.
/// They leave the requested navigation state unchanged. This policy does not
/// govern a standalone screen's missing-host environment fallback, and cannot
/// prevent traps caused by arbitrary consumer code inside a factory or callback.
/// A debug assertion raised from an event callback can stop the process before
/// pending reentrant events are delivered; use eventsOnly for recovery callbacks.
public enum OrbitDiagnostics: Sendable {
    /// Assert after recording rejection in debug builds; reject safely in release.
    /// This is the default. Debug callers may not return after a rejected command.
    case assertInDebug
    /// Emit rejection without asserting, in both debug and release builds.
    /// Useful for tests or consumer-owned logging/recovery policy.
    case eventsOnly
}

/// Native modal style for a registered destination.
public enum OrbitPresentationStyle: Sendable {
    /// A SwiftUI sheet. Configure detents/appearance in ordinary destination content.
    case sheet
    /// A SwiftUI full-screen cover on iOS. Rejected on macOS before state mutation;
    /// it is not silently converted into a sheet.
    case fullScreen
}

/// Stack policy for an ordinary root or modal registered with Orbit.
///
/// Does not change pushed-destination rendering. Recognized ``OrbitTabView``
/// results always start independent tab stacks, irrespective of this option.
public enum OrbitNavigationMode: Sendable {
    /// Provide an Orbit-managed NavigationStack for the root/modal flow.
    /// Default for ordinary routes; do not nest another stack in its content.
    case stack
    /// Render root/modal content without an enclosing Orbit stack.
    /// An advanced opt-out: this flow's router rejects pushes into a missing stack.
    case content
}
