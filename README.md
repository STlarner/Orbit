# Orbit

Dependency-free, imperative navigation for SwiftUI. Declare destinations and
tab content; Orbit handles stacks, selection, bindings and modal lifecycle.

**Requirements:** Swift 6.2+, iOS 17+ or macOS 14+. Full-screen covers and
tab-bar visibility policies are iOS-only. Uses Observation and MainActor.

## Installation

```swift
.package(url: "https://github.com/STlarner/Orbit.git", exact: "0.4.0")
```

Add the `Orbit` product to your target. The repository is currently private;
development and CI require GitHub credentials with repository access.

## Quick start: create, register, display

```swift
import Orbit
import SwiftUI

nonisolated final class HomeRoute: OrbitRoute {}
nonisolated final class DetailRoute: OrbitRoute {
    let title: String
    init(title: String) { self.title = title; super.init() }
}

@main
struct ExampleApp: App {
    @State private var orbit: Orbit

    init() {
        let orbit = Orbit()
        orbit.register(HomeRoute.self) { _ in HomeView() }
        orbit.register(DetailRoute.self) { route in Text(route.title) }
        orbit.setRoot(HomeRoute())
        _orbit = State(initialValue: orbit)
    }

    var body: some Scene {
        WindowGroup { OrbitRootHost(orbit) }
    }
}

struct HomeView: View {
    @Environment(\.orbit) private var orbit

    var body: some View {
        Button("Open detail") { orbit.push(DetailRoute(title: "Detail")) }
    }
}
```

Create one `Orbit` per scene and install one `OrbitRootHost`. No screen needs
its own NavigationStack, binding, context lookup or destination registration.
For asynchronous launch routing, use `OrbitRootHost(orbit) { SplashView() }`:
the placeholder receives the same environment API and can call `setRoot`.

## Tabs: declare content, not infrastructure

Use the same `register` API for screens and tab flows. A factory returning
`OrbitTabView` is automatically registered as a root/modal tab flow:

```swift
orbit.register(HomeTabsRoute.self) { _ in
    OrbitTabView {
        OrbitTabItem(HomeTab()) {
            HomeView()
        } label: {
            Label("Home", systemImage: "house")
        }

        OrbitTabItem(TasksTab()) {
            TasksView()
        } label: {
            Label("Tasks", systemImage: "checklist")
        }
    }
}
```

`HomeTabsRoute` subclasses `OrbitRoute`; `HomeTab` and `TasksTab` subclass
`OrbitTab`. Tab identity is its Swift type, not its display name. The builder
also supports conditions and loops. The declaration is fixed for the lifetime
of that flow; start a new root/modal to change its tab configuration.

Orbit creates the TabView, selection binding, tags, environment routers and
one stack per tab. There is no tab list in `Orbit()` and no public tab manager
or navigation context to assemble. Content and label closures are lazy:
preparing a root does not instantiate tab screens or their ViewModels.

Select a tab from a screen with the same navigation API:

```swift
orbit.selectTab(TasksTab()) // Preserve its stack.
orbit.selectTab(TasksTab(), replacingPath: [taskRoute]) // Replace its stack.
orbit.selectTab(TasksTab(), replacingPath: []) // Show its root screen.
```

Omitted/nil paths preserve the stack. Arrays replace it; other tab stacks
remain unchanged. Invalid tabs/paths reject the entire operation.
The screen's router targets its nearest tab container. A modal with its own
tabs has independent selection and history, even using the same tab types.
An ordinary modal inherits its presenting flow's tab-selection scope.

The scene-owned `Orbit.selectTab` targets the root's tab container, useful for
deep links from services. It is ready synchronously after `setRoot`, before
SwiftUI renders the screens. URL parsing, async entity resolution, cancellation
and whether to dismiss an active modal remain app policy.

### Tab-bar visibility

The default preserves SwiftUI behavior. Choose a policy only if needed:

```swift
OrbitTabView(tabBarVisibility: .hiddenOnPush) { /* tab items */ }
OrbitTabView(tabBarVisibility: .visible) { /* tab items */ }
```

Policies are visual, not different kinds of push. Screen content can still
use normal SwiftUI modifiers. macOS ignores iOS tab-bar visibility policies.

### Root/modal tab flows, not pushed tab stacks

```swift
orbit.setRoot(HomeTabsRoute())
orbit.present(SettingsTabsRoute(), style: .sheet)
```

Each route returning `OrbitTabView` starts its own tab flow. Pushing such a route (or
including it in a replacement path) is rejected explicitly: Orbit does not
promise nested independent NavigationStacks inside a pushed tab container.
A normal SwiftUI TabView that merely groups content may still be pushed as a
regular route; it does not create independent Orbit stacks per tab.

## Navigation commands

```swift
orbit.setRoot(HomeRoute())
orbit.push(DetailRoute(title: "First"))
orbit.pop()
orbit.popToRoot()
orbit.popTo(DetailRoute.self) // Last occurrence of this exact type.
orbit.popTo(routeInstance)   // An exact entry.
orbit.present(ProfileRoute(), style: .sheet)
orbit.present(OnboardingRoute(), style: .fullScreen)
orbit.dismiss()              // Regardless of modal style.
```

Screens read `@Environment(\.orbit)`, which exposes an `OrbitRouter` scoped
to that screen's stack/flow. The scene-owned `Orbit` has root, tab selection,
presentation and `dismissAll` commands, but no ambiguous implicit push target.

- Root/modal routes default to a host-owned stack. Pushed views are rendered
  directly, never wrapped in another stack. Do not nest your own stack there.
- `setRoot` retires the old root and its tab stacks. Active modals remain alive:
  onboarding can replace the root behind itself, then dismiss. An independent
  modal tab flow keeps its own state. `Orbit.dismissAll()` closes all modals.
- The first modal is hosted outside the tab container. Each next modal is
  hosted by its predecessor and has its own identity, stack and lifecycle.
- Swipe, SwiftUI `Environment.dismiss` and programmatic dismissal converge
  through host bindings and `onDismiss`. Contexts are released after animation.
- New presentations while the target modal chain is closing are rejected, not
  timed or queued. A completed `.dismissed` event may request the next modal.
- Commands that can be rejected return `Bool` (`@discardableResult`). Empty
  stack pops and dismiss without a presentation are harmless no-ops.
- Routes use instance identity. Create a new instance per stack entry;
  duplicate occurrences of the same instance are rejected. Payloads belong to
  the app, and routes are not automatically Codable or Sendable.

For unusual non-stack roots/modals, `register(_:navigation: .content)` remains
an advanced opt-out. Do not specify it for tabs: return `OrbitTabView` and Orbit
recognizes the flow, including when a factory is forwarded through a generic
View parameter. Orbit checks the factory's result type, not the rendered view
hierarchy. Wrapping a container in a Group, AnyView or a SwiftUI modifier changes
that result type and is not inferred as a tab flow; style its tab content instead.

## Optional navigation diagnostics

```swift
let orbit = Orbit()
orbit.onNavigationEvent = { event in
    // Adapt to your logger or analytics; runs synchronously on MainActor.
    print(event.kind, event.routeName ?? "", event.path, event.message)
}
```

This callback observes navigation events and rejected commands. It is **not an
interceptor** and does not approve or block requests. It is optional and has no
logger dependency. Events contain identities/names, never route payloads.
Path events include back gestures; dismissal events include interactive close.
Avoid retain cycles when capturing the scene owner in a callback.

Default diagnostics assert in debug and reject safely in release. Use
`Orbit(diagnostics: .eventsOnly)` for tests or a custom recovery policy.
Missing/duplicate registrations and empty/duplicate tab declarations are
reported without changing the current root, modal or stack.

## Development and status

```sh
swift build --build-tests
xcodebuild -scheme Orbit -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build-for-testing
```

These compile library and tests without execution. Run tests explicitly with
`swift test` or Xcode's test action. See [the complete app example](Examples/OrbitDemo.swift).

Version 0.4.0 is pre-1.0. Regression tests cover preparation before rendering,
scoped modal tabs, invalidation, selection policies and presentation lifecycle.
Gestures/visual transitions still require simulator/device validation. State
restoration and pushed independent tab flows are not supported in this release.
