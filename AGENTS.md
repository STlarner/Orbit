# Orbit

Orbit is a dependency-free SwiftUI navigation package. Use Swift 6, explicit
`@MainActor` isolation for navigation state, and Observation (not Combine).
Public types use the Orbit prefix; `Orbit` is the scene-scoped owner.

- Keep app routes, DI containers, URL parsing and loggers outside this package.
- Route identity is per instance; tab and registry identity is per Swift type.
- Hosts own bindings and SwiftUI presentation lifecycle, not destination views.
- Preserve presented flows when replacing the root; dismiss is explicit.
- Create `Orbit()` without tabs. The single generic `register` recognizes
  OrbitTabFlow metadata, including ModifiedContent chains. Use `wrapped` for
  type-erased/custom decoration; never inspect private SwiftUI view storage.
  Retain the complete decorated view, not only its underlying tab declaration.
- Tab flows may be roots or modals, never pushed independent stacks. Prepare
  their declarations before publishing navigation, but keep screen factories lazy.
- `selectTab(_:replacingPath:)` targets the router's nearest tab flow (the scene
  owner targets its root). nil preserves the stack; an array replaces it; [] clears it.
- `onNavigationEvent` is optional observation, not interception or a logger dependency.
- Complete every command mutation before delivering its event batch. Reentrant
  callback commands append events after the current batch; never recursively
  notify observers or resume a partially updated operation after callbacks.
- Use Swift Testing and hand-written test doubles. Do not run tests unless asked.
- Build the library and test targets after Swift changes.
- Update README and CHANGELOG when changing public contracts.
- Public README is usage documentation: describe implemented behavior and
  examples, not lists of absent dependencies or internal agent instructions.
- Workflow guides belong in the module's DocC catalog. The public reference
  follows main, not a release tag. GitHub Actions validates PR documentation
  and publishes only from main; previews are downloadable artifacts.
- `python3 Scripts/build_documentation.py` checks iOS comment coverage and
  builds the static site with DocC warnings as errors. Then run
  `python3 Scripts/check_examples.py` to compile all Swift documentation fences
  and the standalone demo. These validation commands do not execute unit tests.
- Never rewrite a published version tag; release a new version instead.
