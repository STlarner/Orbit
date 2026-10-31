# Orbit

Orbit is a dependency-free SwiftUI navigation package. Use Swift 6, explicit
`@MainActor` isolation for navigation state, and Observation (not Combine).
Public types use the Orbit prefix; `Orbit` is the scene-scoped owner.

- Keep app routes, DI containers, URL parsing and loggers outside this package.
- Route identity is per instance; tab and registry identity is per Swift type.
- Hosts own bindings and SwiftUI presentation lifecycle, not destination views.
- Preserve presented flows when replacing the root; dismiss is explicit.
- Tab selection is `select(_:replacingPath:)` (or router `selectTab`): nil
  preserves its stack; an array replaces it; [] selects its root screen.
- Use Swift Testing and hand-written test doubles. Do not run tests unless asked.
- Build the library and test targets after Swift changes.
- Update README and CHANGELOG when changing public contracts.
- Never rewrite a published version tag; release a new version instead.
