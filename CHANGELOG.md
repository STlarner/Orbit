# Changelog

## 0.5.0

- Fix tab-flow recognition through native SwiftUI ModifiedContent modifier chains.
- Add OrbitTabFlow metadata and `wrapped` / OrbitWrappedTabFlow for Group, AnyView
  and custom decoration, without private SwiftUI reflection.
- Retain the full decorated view for rendering, while validating its original
  tab declaration before root/modal state changes. Use one generic register API.
- Complete multi-step mutations before delivering events. Reentrant commands
  enqueue their events after the current batch, without recursive callbacks.
- Add regression coverage for decorated, erased and custom tab flows, validation
  before replacement, callback-visible selection and nested root replacement.

- Document every source-declared public API with DocC parameters, results,
  scopes, defaults, event timing and limitations; add a module documentation catalog.
- Rewrite README with a full API reference and usage/validation guidance.
- Correct the example and quick start to create a separate Orbit per window.
- Record static review findings and outstanding runtime validation in REVIEW.md.

## 0.4.0

- **Breaking:** remove the public `registerTabs` API. Use `register` for every
  destination; factories returning `OrbitTabView` are recognized as tab flows.
- Support the concrete overload and generic factory forwarding without
  rendering or inspecting a SwiftUI view hierarchy during registration.
- Update the app example and add a generic-forwarding regression test.

## 0.3.0

- **Breaking:** create `Orbit()` without a scene-wide tab list. Register tab
  flows with `registerTabs` and declare content via `OrbitTabView` / `OrbitTabItem`.
- Tab managers, contexts and navigation stack hosts are now internal. Consumers
  no longer construct selection bindings, tags, per-tab stacks or environment wiring.
- Prepare tab flows before publishing root/presentation events; keep screen factories lazy.
- Root and modal tab flows have independent state; routers select their nearest
  tab container. `Orbit.selectTab` targets the root flow for service/deep-link use.
- Reject pushing registered tab flows, including through replacement paths.
- Add optional `OrbitTabBarVisibility` policy; default is native SwiftUI behavior.
- **Breaking:** rename `onEvent` to `onNavigationEvent`, configured separately
  from initialization, and document that it is observation, not interception.
- Retire old root tab contexts on root replacement while preserving active modals.
- Simplify the example and add regression tests for scoped tab flows and lazy setup.

## 0.2.0

- **Breaking:** remove `OrbitTabManager.navigate(to:path:)`. Use the existing
  tab-selection API with an optional explicit stack replacement:
  `select(_:replacingPath:)`. Omitted/nil paths preserve the stack; [] clears it.
- Expose the same optional replacement through `OrbitRouter.selectTab`.
- Validate replacement paths before changing either selection or stack.
- Add tests for preservation, replacement, reset, router forwarding and rejection.

## 0.1.1

- Release modal state before emitting completed-dismissal callbacks, allowing
  consumers to immediately request the next presentation.
- Reject presentation and push commands from flows whose modal ancestor is
  closing, and ignore stale/unsolicited completion callbacks.
- Add regression tests for both lifecycle cases.

## 0.1.0

- Initial dependency-free Swift 6 navigation package.
- Scene root host, imperative context routers and shared typed route registry.
- Independent tab stacks and synchronous tab/path navigation.
- Sheet/full-screen presentation style and independent nested modal contexts.
- Identity-safe dismissal cleanup and interactive navigation events.
- Optional diagnostics callback with no logger or DI dependency.
- Swift Testing coverage, build-only CI and a SwiftUI integration example.
