# Orbit code review

Initial review covered runtime/API version **0.4.0**, including every package source, package
manifest, example, model tests, build workflow and TidyMa navigation integration.
This is a static review plus build/documentation validation, not a device test.
No unit/UI tests were executed. The follow-up fixes below are included in **0.5.0**.

## Findings

### P1 — Event callbacks can mutate an operation halfway through its state update

**Fixed in 0.5.0.** `Sources/Orbit/OrbitTabManager.swift`, `select(_:replacingPath:)`;
`Sources/Orbit/OrbitContext.swift`, `updatePath(_:)`; `Sources/Orbit/Orbit.swift`,
`setRoot(_:)` and `emit`.

Replacing a tab path calls `updatePath`, which synchronously emits `.pathChanged`
before the selection assignment. If the callback calls `setRoot`, it retires
the old tab contexts. The original `select` then resumes against its captured
old manager, assigns an orphaned selection, emits `.tabSelected` through the
scene root and returns `true`, although the target flow is gone. Root replacement
also emits a path event before installing/publishing its new root, so nested
root changes can be overwritten by the outer command.

This does not require competing threads: MainActor does not prevent synchronous
callback reentrancy. TidyMa's current callback only logs, so that integration
does not exercise the problematic case.

**Resolution:** all state mutations complete before event delivery. Nested
internal updates join the command's batch. Commands issued by a callback mutate
their state immediately, but their immutable event snapshots follow the current
batch in FIFO order, without recursively invoking observers. There is no async
delay or generation counter. Regression tests cover completed selection visible
to callbacks and root replacement that cannot be overwritten by an outer command.
The existing after-cleanup `.dismissed` behavior is preserved. Consumers still
must avoid unbounded event/command feedback loops and treat events as snapshots.

### P2 — Natural SwiftUI wrappers disable tab inference after registration succeeds

**Fixed with metadata-preserving decoration in 0.5.0.** `Sources/Orbit/RouteRegistry.swift`, `register`;
`Sources/Orbit/OrbitTabView.swift`, the unmatched-context branch in `body`.

Only an exact `OrbitTabView` result is recognized. For example,
`OrbitTabView { ... }.preferredColorScheme(.dark)` is a different concrete type.
It is stored as an ordinary registration. `setRoot` can return `true` and replace
the previous root; on appearance the nested container then reports rejection
and renders empty content (or asserts with default development diagnostics).

This is particularly easy to hit when adding detents, appearance modifiers or
a reusable wrapper view. It conflicts with an intuitive expectation that
invalid tab configuration is always rejected before root replacement.

**Resolution:** the single generic `register` recognizes OrbitTabFlow. OrbitTabView
and native ModifiedContent chains conform; their public metadata preserves the
original declaration while PreparedTabFlow retains the complete decorated view.
Padding/preferred-color-scheme chains are no longer mistaken for ordinary roots.

For AnyView, Group, transformations that are not ModifiedContent, and arbitrary
wrappers, `wrapped { ... }` preserves that metadata explicitly. Custom reusable
views may instead conform to OrbitTabFlow with a stable stored declaration.
No private SwiftUI reflection or body evaluation is used during registration.
Tests cover native decoration, Group/AnyView decoration, custom wrappers, lazy
content and invalid declarations rejected before root/modal replacement.

**Boundary:** raw opaque wrappers cannot be inferred if they discard the public
metadata. Use the supported wrapper API; do not claim arbitrary AnyView or view
hierarchy detection. Actual rendered modifier behavior still needs UI validation.

### P2 — The previous example shared one navigation owner between windows

**Fixed in documentation/example code.** `Examples/OrbitDemo.swift` and README
quick start previously stored Orbit in `App`, outside `WindowGroup` content.
Multiple windows would share root/path/presentation state and install multiple
active hosts for the same owner. One window's dismissal could invalidate state
used by another. The example now stores Orbit in a window-root View.

TidyMa still uses an app-container-scoped Orbit. This is appropriate only while
it is deliberately single-scene. Supporting independent windows would require
scene-specific Orbit/deep-link wiring; that app redesign was not performed here.

### Validation gap — Model tests do not confirm SwiftUI presentation lifecycle

**Open validation work, not a proven runtime defect.** Existing tests directly
call `requestDismiss` / `completeDismiss`. They cover IDs, cleanup and ownership,
but do not mount a real `OrbitRootHost`, drive swipe dismissal, verify callback
identity after transitions, or exercise mixed nested sheets/covers on devices.
CI compiles these tests but intentionally does not run them.

`present` marks model state active before SwiftUI mounts its view. A following
request may target that not-yet-mounted modal; `.presented` is not a readiness
signal. This needs UI validation on the supported OS versions before promising
reliable chained transition timing. Arbitrary sleeps are not a sound fix.

## Other contract clarifications

- A route registration matches an exact type, not its subclasses or name.
- Reusing the same root instance keeps its root view ID, even though paths reset.
- `dismissAll` invalidates descendants with their parent; it does not emit one
  completed-dismissal event per descendant.
- Tab-selection event paths refer to the flow context, not the selected tab path.
- Factories are lazy relative to registration, not single-shot constructors.
- Routers are stack/flow-scoped. Applications must cancel async work belonging
  to a popped screen; retaining the shared stack router does not cancel that work.
- The missing-host fallback has no owner to receive diagnostic events.

## Changes in this review pass

- Added parameter/result/scope/limitation DocC comments to every source-declared
  public type, member, enum case, convenience overload and builder hook.
- Added a DocC module catalog and a complete public-API README reference.
- Corrected example ownership to one Orbit per window.
- The initial review documented findings without runtime changes. Its follow-up
  fixes P1/P2 in 0.5.0, without rewriting any published version tag.

## Validation completed

- `swift build --build-tests`: library and macOS test targets compile.
- `xcodebuild build-for-testing`: iOS Simulator library/test targets compile.
- `xcodebuild docbuild`: DocC archive builds without documentation diagnostics.
- Generated symbol graphs: the initial review documented **80/80** source APIs;
  the 0.5.0 follow-up documents **92/92**, including added flow/wrapper APIs.
- Standalone demo and the README quick-start code both pass Swift 6 type checking.
- `git diff --check`: clean.

Validated with Xcode 26.6. These are compilation/documentation checks, not test
execution or confirmation of iOS 27 simulator behavior. The initial review was
local; the follow-up is versioned independently as 0.5.0 for app integration.
