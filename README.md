# Orbit

**Imperative navigation for SwiftUI, without destination coupling.** Screens
request routes; Orbit owns stacks, tab selection and modal presentation lifecycle.
No logger, DI container, URL parser or app models are required.

Swift **6.2+** · iOS **17+** · macOS **14+** · Observation · MainActor

## Install

```swift
.package(url: "https://github.com/STlarner/Orbit.git", exact: "0.5.0")
```

Add the `Orbit` product to your app target. The repository is currently private:
Xcode, command-line builds and CI need GitHub credentials with repository access.

## Start with three things

1. Create an `Orbit()` **for each window**.
2. Register route-to-view factories.
3. Install one `OrbitRootHost` for that owner.

```swift
import Orbit
import SwiftUI

nonisolated final class HomeRoute: OrbitRoute {}
nonisolated final class DetailRoute: OrbitRoute {
    let title: String

    init(title: String) {
        self.title = title
        super.init()
    }
}

@main
struct ExampleApp: App {
    var body: some Scene {
        WindowGroup { ExampleWindow() }
    }
}

@MainActor
struct ExampleWindow: View {
    @State private var orbit: Orbit

    init() {
        let orbit = Orbit()
        orbit.register(HomeRoute.self) { _ in HomeView() }
        orbit.register(DetailRoute.self) { route in Text(route.title) }
        orbit.setRoot(HomeRoute())
        _orbit = State(initialValue: orbit)
    }

    var body: some View { OrbitRootHost(orbit) }
}

struct HomeView: View {
    @Environment(\.orbit) private var orbit

    var body: some View {
        Button("Open detail") {
            orbit.push(DetailRoute(title: "Detail"))
        }
        .navigationTitle("Home")
    }
}
```

Do not put one navigation owner in `App` and share it between `WindowGroup`
windows: that would share their paths and presentation lifecycle. Services and
repositories can be app-scoped; navigation state should remain window-scoped.
For a deliberately single-window app, a scene-specific DI registration is fine.

### Resolve the first root asynchronously

```swift
OrbitRootHost(orbit) {
    SplashView() // Reads @Environment(\.orbit), then calls setRoot.
}
```

The placeholder appears while `rootRoute == nil`. It is not wrapped in a stack;
there is no pushed path before a root exists. Use cancellable `.task` work to
resolve a launch destination. Without a placeholder, the host uses `EmptyView`.

## Tabs are content declarations

Use **the same `register`** for ordinary views and independent tab flows:

```swift
nonisolated final class HomeTabsRoute: OrbitRoute {}
nonisolated final class HomeTab: OrbitTab {}
nonisolated final class TasksTab: OrbitTab {}

orbit.register(HomeTabsRoute.self) { _ in
    OrbitTabView(tabBarVisibility: .hiddenOnPush) {
        OrbitTabItem(HomeTab()) {
            HomeView()
        } label: {
            Label("Home", systemImage: "house")
        }

        OrbitTabItem(TasksTab()) {
            TasksView() // Your app's screen.
        } label: {
            Label("Tasks", systemImage: "checklist")
        }
    }
}
```

An `OrbitTabFlow` result identifies a tab flow, including OrbitTabView, native
ModifiedContent modifier chains and generic factory forwarding. Orbit builds
native tab selection, bindings, tags,
environment routers and one independent stack per tab. No contexts or manager
objects are part of consumer setup.

### Decorating the complete tab container

Native ModifiedContent chains preserve the flow, including common modifiers
such as padding and preferred color scheme. Orbit retains the **decorated view**
for rendering, not just the undecorated tab declaration:

```swift
orbit.register(HomeTabsRoute.self) { _ in
    OrbitTabView {
        OrbitTabItem(HomeTab()) { HomeView() } label: { Text("Home") }
        OrbitTabItem(TasksTab()) { TasksView() } label: { Text("Tasks") }
    }
    .padding()
    .preferredColorScheme(.dark)
}
```

For Group, AnyView or transformations that hide the source flow, wrap the
decoration with `wrapped` **on the original flow**:

```swift
orbit.register(HomeTabsRoute.self) { _ in
    OrbitTabView {
        OrbitTabItem(HomeTab()) { HomeView() } label: { Text("Home") }
    }
    .wrapped { tabs in
        AnyView(Group { tabs }.padding())
    }
}
```

Render the supplied flow exactly once. The wrapper preserves declaration
identity, lazy tab content, validation and the entire decorated rendering.
Custom reusable View wrappers can alternatively conform to `OrbitTabFlow` and
expose the same stored `orbitTabView` that their body renders. Orbit never
reflects into private SwiftUI storage. Raw AnyView/Group/custom wrappers without
preserved metadata still cannot be inferred: use `wrapped` rather than hiding
the flow. Not every SwiftUI transformation returns ModifiedContent; `wrapped`
is also the escape hatch for those transformations.

The tab declaration builder supports items, conditions and loops. It executes
as the root/modal request is prepared, and is fixed for that flow's lifetime.
Empty declarations and duplicate tab types are rejected before a recognized
flow replaces the current state. **Content and label closures are lazy**, but
may run repeatedly during SwiftUI rendering; keep one-shot work in `.task` or
your ViewModel rather than in a factory.

### Selection and optional stack replacement

```swift
orbit.selectTab(TasksTab()) // Preserve the existing stack.
orbit.selectTab(TasksTab(), replacingPath: [resolvedRoute]) // Replace it.
orbit.selectTab(TasksTab(), replacingPath: []) // Show the tab's root screen.
```

`nil` preserves the path; an array replaces the whole path. Other tab histories
are unchanged. Unknown tabs, unregistered entries, duplicate route instances or
independent tab-flow entries reject the selection/replacement together.

An environment router selects its **nearest tab container**. Modal tab flows
have independent state, even using the same tab types as the root. Ordinary
modals inherit their presenter's tab scope. The scene-owned `Orbit.selectTab`
always targets the root's tabs and is ready after `setRoot`, before rendering.

### Tab-bar visibility

| Policy | iOS behavior |
|---|---|
| `.automatic` | SwiftUI's automatic visibility preference; default. |
| `.visible` | Requests visibility even with a nonempty pushed path. |
| `.hiddenOnPush` | Automatic at the tab root; hidden with pushed entries. |

The policy changes visuals, not navigation. It is ignored on macOS. Content can
also express native SwiftUI toolbar preferences.

## Navigation API reference

All commands/factories run on **MainActor**. `Bool` means the state request was
accepted, **not** that the transition has completed. Default diagnostics assert
in debug on reported validation failures; with `.eventsOnly` or release builds,
fallible commands return `false`. No timers or implicit request queue are used.

### Scene owner: `Orbit`

| Public API | Contract |
|---|---|
| `init(diagnostics: = .assertInDebug)` | Empty registry, no root and no tabs. |
| `rootRoute` | Observable, read-only current root; initially `nil`. |
| `register(_:navigation: = .stack, factory:) -> Bool` | Single generic API for all views. Stores an exact-type factory; OrbitTabFlow results preserve tab metadata and decorated content, overriding the ordinary stack mode. Duplicate registration is rejected. |
| `setRoot(_:) -> Bool` | Validates the route/tab declaration, clears old root paths and retires old root tabs. Preserves active modals. |
| `selectTab(_:replacingPath: = nil) -> Bool` | Targets root tabs; optional whole-path replacement. Does not dismiss modals. |
| `present(_:style: = .sheet) -> Bool` | Requests a modal above the root's current presentation chain. |
| `dismissAll()` | Requests dismissal of the entire modal chain; root/tab paths stay unchanged. |
| `onNavigationEvent` | Optional synchronous `(OrbitEvent) -> Void` observer; assign `nil` to remove it. |

Factories are retained by the owner. Ordinary factories run during rendering;
tab-declaration factories run while a root/modal request is prepared, before
its publication. The factory itself is never run by `register`. Keep factories
free of navigation side effects and avoid capturing the owner strongly.

Use a **fresh route instance** to restart root view identity. Setting the same
root instance again clears paths, but its unchanged ID may preserve view-local
SwiftUI state.

### Screen commands: `OrbitRouter`

Read the protocol with `@Environment(\.orbit)`. It targets the screen's stack,
not an implicit scene-wide push destination. Custom conformances can be injected
into standalone previews/test screens with `.environment(\.orbit, router)`.

| Public API | Contract |
|---|---|
| `setRoot(_:) -> Bool` | Scene-wide root replacement through the owner; preserves active modals. |
| `push(_:) -> Bool` | Append to this stack. Rejects unregistered/repeated instances, tab flows, non-stack root/modal flows and closing modal contexts. |
| `pop()` | Remove the last pushed entry; empty stack is a no-op. |
| `popToRoot()` | Clear pushed entries; does not dismiss the enclosing modal. |
| `popTo(RouteType.self)` | Keep the last entry of that exact type and remove entries after it. No subclass matching. |
| `popTo(routeInstance)` | Keep that exact reference and remove entries after it. Equal payloads do not match. |
| `selectTab(_:replacingPath:) -> Bool` | Select in the nearest tab scope; `nil` preserves, array replaces, `[]` clears. |
| `selectTab(_:) -> Bool` | Convenience call preserving the tab's path. |
| `present(_:style:) -> Bool` | Present in the enclosing flow's modal chain; tab flows are allowed. |
| `present(_:) -> Bool` | Convenience call using `.sheet`. |
| `dismiss()` | Close this modal flow and descendants, not a stack entry. A modal-tab router closes its enclosing modal. A root router closes its presented flow. |

`popTo` searches **pushed entries**, not the stack root; absent targets are
no-ops. Routers retained after complete flow retirement no longer navigate.
Cancel obsolete screen tasks yourself: a router belongs to a stack/flow, not
to the lifetime of each individual pushed view.

### Rendering and declaration types

| Public type/member | Purpose |
|---|---|
| `OrbitRootHost.init(_:placeholder:)` | One host per owner; placeholder while no root exists. |
| `OrbitRootHost.init(_:)` | Host with an `EmptyView` placeholder. |
| `OrbitRootHost.body` | Root/placeholder rendering, routing environment and modal lifecycle. |
| `OrbitTabView.init(tabBarVisibility: = .automatic, content:)` | Evaluate an ordered tab declaration; stores lazy screen/label factories. |
| `OrbitTabView.body` | Native tab container/stacks for its matching registered flow. |
| `OrbitTabItem.init(_:content:label:)` | Declare exact-type tab key, root content and standard tab label. |
| `OrbitTabFlow.orbitTabView` | Original stored declaration that the conforming view renders; must have stable identity. |
| `OrbitTabFlow.wrapped(content:)` | Preserve flow metadata while decorating through Group, AnyView or arbitrary wrappers. Include the supplied flow exactly once. |
| `OrbitWrappedTabFlow.init(_:content:)` | Explicit constructor for the metadata-preserving decorated view; usually use `wrapped`. |
| `OrbitWrappedTabFlow.orbitTabView` / `body` | Original declaration and complete decorated rendering. |
| `OrbitTabView.orbitTabView` | Its own declaration, making a bare container a tab flow. |
| `ModifiedContent.orbitTabView` | Available when content preserves OrbitTabFlow and the modifier is a ViewModifier; forwards original metadata without reflection. |
| `OrbitTabBuilder.buildExpression(_:)` | Compiler hook turning one item into a declaration component. |
| `OrbitTabBuilder.buildBlock(_:)` | Flatten components in source order. |
| `OrbitTabBuilder.buildOptional(_:)` | Support `if` without `else`. |
| `OrbitTabBuilder.buildEither(first:)` / `buildEither(second:)` | Support either selected branch of `if/else`. |
| `OrbitTabBuilder.buildArray(_:)` | Flatten loop iterations in order. |
| `EnvironmentValues.orbit` | Main-actor get/set router dependency; supplied by hosts. |

Builder methods are compiler plumbing; applications normally use only the DSL.
Without a host, reading the environment router is allowed, but invoking it
asserts in debug and becomes a no-op/`false` in release. No owner exists there
to receive rejection events. A standalone `OrbitTabView` without a matching
registered flow displays no content.

### Identity types and policy enums

| Public API | Contract |
|---|---|
| `OrbitRoute.init()` | New reference-based destination identity; subclasses call `super.init()`. |
| `OrbitRoute.id` | Live `ObjectIdentifier`; not a restoration/persistent ID. |
| `OrbitRoute.routeName` / `name` | Overridable type diagnostic label and instance shorthand. |
| `OrbitRoute.==` / `hash(into:)` | Reference identity, independent of payload. |
| `OrbitTab.init()` | Tab key; same concrete type means equal, even with new instances. |
| `OrbitTab.tabName` / `name` | Overridable diagnostic label and instance shorthand. |
| `OrbitTab.==` / `hash(into:)` | Exact concrete type identity, not names or payload. |
| `OrbitNavigationMode.stack` | Default Orbit-managed root/modal stack; do not nest another independent stack. |
| `OrbitNavigationMode.content` | Advanced root/modal opt-out; no Orbit stack to push into. Does not configure recognized tab flows. |
| `OrbitPresentationStyle.sheet` | Native sheet; ordinary destination content can set appearance/detents. |
| `OrbitPresentationStyle.fullScreen` | iOS-only full-screen cover; rejected on macOS. |
| `OrbitDiagnostics.assertInDebug` | Rejection event then debug assertion; safe rejection in release. |
| `OrbitDiagnostics.eventsOnly` | Rejection events without development assertions. |

Routes/tabs are nonisolated types, but their payloads are not implicitly
Sendable. Registration keys use exact type identity, including across modules;
base registrations do not automatically register subclasses. Route restoration,
serialization and domain-ID mapping remain the application's responsibility.

## Modal lifecycle

The first modal is hosted outside its root/tab container; each next modal is
hosted by its predecessor. Every modal has independent path/tab state.
`dismiss` is separate from `pop`, and works regardless of modal style.

SwiftUI swipe dismissal, `Environment.dismiss` and programmatic dismissal pass
through host bindings and cleanup. Contexts remain alive during the close
animation, then are invalidated. Closing an outer flow invalidates descendants
without a separate `.dismissed` event for every descendant. New requests while
the target chain is closing are rejected, not queued.

An accepted `present` does **not** guarantee that the modal is mounted yet.
Orbit currently has no presentation-completion/readiness callback. Do not use
`.presented` as a signal that it is safe to start another UI transition.

## Events and diagnostics

```swift
orbit.onNavigationEvent = { event in
    print(event.kind, event.routeName ?? "", event.path, event.message)
}
```

`OrbitEvent` is a Sendable, read-only value emitted by Orbit, with no public
memberwise initializer. `Kind` is a String-backed enum whose raw values match
its case names. No destination payload is automatically logged.

| Public field | Meaning |
|---|---|
| `kind` | Operation category below. |
| `contextID` | Optional diagnostic stack/flow UUID, not a tab or route ID. |
| `routeName` | Usually populated for root/presentation events; otherwise `nil`. |
| `path` | Involved context's pushed route names, excluding its root. A tab-selection event refers to its containing flow, not the selected tab's path. |
| `message` | Diagnostic detail, often empty. Not a localized message or stable error code. |

| `OrbitEvent.Kind` case | Timing |
|---|---|
| `.rootChanged` | Accepted root stored; its tab state is ready. |
| `.pathChanged` | Pushed path changed, including back gestures. |
| `.tabSelected` | Accepted selection request; can occur even for the already selected tab. |
| `.presented` | Modal state accepted, not necessarily visible. |
| `.dismissalRequested` | Close requested; cleanup still pending. |
| `.dismissed` | Explicitly closed flow cleaned up; path snapshot is empty. |
| `.rejected` | Validation/configuration rejection, before any default debug assertion. |

The observer is synchronous on MainActor, not an interceptor. Keep it short and
capture the owner weakly if needed. **All state changes finish before a command's
event batch is delivered.** A path event from `selectTab` therefore sees selection
already applied, and a root-path reset event sees the replacement root prepared.

Callbacks may directly issue another command. That command completes its own
state update immediately, while its events follow the current batch in FIFO
order instead of recursively calling the observer. Events are immutable snapshots
of their originating operations; live state may have been changed by an earlier
callback by the time a later snapshot is delivered. Avoid unbounded feedback
loops when reacting to your own generated events. Dismissal events are still
sent only after cleanup, allowing the next presentation to be requested.

Validation records a rejection before the default debug assertion. An assertion
inside a callback can stop the process before queued reentrant events are
delivered; use `.eventsOnly` for callbacks intended to recover from invalid input.

## DI, previews and deep links

Factories are the composition point for your own DI system:

```swift
orbit.register(DetailRoute.self) { route in
    DetailView(viewModel: makeDetailViewModel(title: route.title))
}
```

Resolve tab ViewModels **inside** each item content closure to keep them lazy.
Orbit does not import Swinject or another container. Standalone screens can
receive a custom `OrbitRouter` in previews; the supplied host installs its own
router internally, so place overrides on screen content when necessary.

Parse URLs, authorize navigation and resolve entities in the app. Once the
request is still valid, use the scene owner's selection API:

```swift
orbit.selectTab(TasksTab(), replacingPath: [resolvedRoute])
```

It targets root tabs without a delayed push or waiting for rendering. Cancel
old async requests and check root/request validity before applying results.
Whether an active modal should be closed first is application policy.

## Known limitations and review status

This is **pre-1.0** code. See [REVIEW.md](REVIEW.md) for the review findings.

- Native ModifiedContent decoration preserves tab metadata. For wrappers that
  erase it, use `wrapped` or a custom OrbitTabFlow conformance. Arbitrary hidden
  view hierarchies cannot be detected through public SwiftUI APIs.
- Event callbacks support reentrant commands with FIFO delivery, but consumers
  remain responsible for avoiding infinite event-to-command feedback loops.
- Independent tab flows may be roots or modals, never pushed entries.
- No presentation-readiness signal, restoration, split-view support or UIKit
  controller lookup is provided.
- State tests exercise model lifecycle; they do not validate actual SwiftUI
  animation, gestures, nested sheet/cover mounting or OS-specific console warnings.

## Documentation and validation

All source-declared public APIs have DocC comments describing parameters,
defaults, scopes, results and limits. Open the package in Xcode and use
**Product → Build Documentation**, or:

```sh
xcodebuild -scheme Orbit -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO docbuild
```

Compile the library and test targets without executing tests:

```sh
swift build --build-tests
xcodebuild -scheme Orbit -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build-for-testing
```

Run `swift test` or Xcode's test action only when you want test execution.
The [complete example](Examples/OrbitDemo.swift) is consumer integration source,
not a packaged app target; it demonstrates a separate owner for each window.
