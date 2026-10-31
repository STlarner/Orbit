# Orbit

Dependency-free, imperative navigation for SwiftUI. Screens request routes;
Orbit's hosts own stacks, destination rendering and presentation lifecycle.

**Requirements:** Swift 6.2+, iOS 17+ or macOS 14+. Full-screen covers are iOS-only.
The package uses Swift 6 language mode, Observation and explicit main-actor
isolation. It has no DI container, logger, URL parser or app-specific models.

## Installation

```swift
.package(url: "https://github.com/STlarner/Orbit.git", exact: "0.1.1")
```

Add the `Orbit` product to your target. While the repository is private, both
local development and CI require GitHub credentials with repository access.

## Start before the first screen

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
        let navigation = Orbit()
        navigation.register(HomeRoute.self) { _ in HomeView() }
        navigation.register(DetailRoute.self) { route in Text(route.title) }
        _orbit = State(initialValue: navigation)
    }

    var body: some Scene {
        WindowGroup {
            OrbitRootHost(orbit) {
                ProgressView().task { orbit.setRoot(HomeRoute()) }
            }
        }
    }
}

struct HomeView: View {
    @Environment(\.orbit) private var orbit

    var body: some View {
        Button("Open detail") {
            orbit.push(DetailRoute(title: "Detail"))
        }
    }
}
```

Create one `Orbit` per scene, keep it alive, and install one `OrbitRootHost`
outside the root route. The placeholder receives a router too, so a splash
screen can resolve and set the first root. `Orbit` itself does not have an
implicit push target; use the environment router or an explicit tab context.

## Commands

```swift
orbit.setRoot(HomeRoute())
orbit.push(DetailRoute(title: "First"))
orbit.pop()
orbit.popToRoot()
orbit.popTo(DetailRoute.self) // Last occurrence of this exact type.
orbit.popTo(routeInstance)   // An exact entry.
orbit.selectTab(TasksTab())
orbit.present(ProfileRoute(), style: .sheet)
orbit.present(OnboardingRoute(), style: .fullScreen)
orbit.dismiss()              // No need to know the presentation style.
```

Mutating commands that can be rejected return `Bool` (`@discardableResult`).
Empty-stack pops and dismiss without a presentation are harmless no-ops.
`OrbitRouter` has no SwiftUI rendering or binding methods.

## Tabs

Define subclasses of `OrbitTab`, then initialize:

```swift
let orbit = Orbit(tabs: [HomeTab(), TasksTab()])
orbit.register(TabsRoute.self, navigation: .content) { _ in TabsView() }
```

In `TabsView`, read `@Environment(\.orbitTabs)`, and use the manager's
`selectedTab` with a binding that calls `select`. Tag tabs with
`HomeTab() as OrbitTab?` / `TasksTab() as OrbitTab?`. Wrap each tab's root
content in `OrbitNavigationHost(context)` using `tabs.context(for:)`.
See [the complete example](Examples/OrbitDemo.swift).

Every tab has an independent stack. Names are diagnostic labels only: tab
equality and registry keys use concrete type identity, even across modules.
Empty tab lists have `selectedTab == nil`; unknown tabs and duplicate types
produce diagnostics rather than force unwraps or dictionary crashes.

For a resolved deep-link destination, atomically update stack and selection:

```swift
orbit.tabs.navigate(to: TasksTab(), path: [resolvedRoute])
```

No delayed push is scheduled. The app still owns URL parsing, asynchronous
entity resolution, request cancellation and whether an active modal should
be dismissed first. `Orbit` does not impose authentication/onboarding policy.

## Roots, stacks and presentations

- Registration defaults to `.stack`: when a route starts a root or modal flow,
  Orbit provides its `NavigationStack`. Do not add another stack in that view.
- Register tab containers or custom non-stack flows with `.content`.
- Pushed destinations are rendered directly, never wrapped in another stack.
- `setRoot` resets root and tab paths and selects the first tab. It preserves
  active modals deliberately: onboarding can replace the root behind itself,
  then call `dismiss`. Call `Orbit.dismissAll()` to close the full modal chain.
- A presentation from a tab is hosted outside `TabView`. Nested presentations
  are hosted by the preceding modal. There is no public global/local target.
- Each modal has its own context and presentation identity. A nested router's
  `dismiss` closes its own flow, leaving its parent modal open.
- Programmatic dismissal, swipe dismissal and SwiftUI `Environment.dismiss`
  converge through host bindings and `onDismiss`. Contexts remain retained
  until dismissal completes, then their descendants are invalidated/released.
- Requests to present while a modal in the target chain is closing are
  rejected. They are not silently queued or timed. Retry after `.dismissed`.

Payloads belong to the app. Routes use instance identity; create a new instance
for every stack entry. Duplicate occurrences of the same instance are rejected.
Routes are not automatically `Codable` or `Sendable`; restoration is not part
of this initial release.

## Diagnostics, without a logger dependency

```swift
let orbit = Orbit(diagnostics: .assertInDebug)
orbit.onEvent = { event in
    // Adapt to your logger or analytics. Runs synchronously on MainActor.
    print(event.kind, event.routeName ?? "", event.path, event.message)
}
```

Default diagnostics assert in debug builds and reject safely in release.
Use `.eventsOnly` for tests or a custom recovery policy. Register routes before
navigating; missing factories and duplicate registrations emit `.rejected`
without changing state. No route payload is included in events.
Path events include interactive back navigation. Presentation events include
request, dismissal request and completed dismissal.

Avoid callback retain cycles (capture the owner weakly if necessary).
Factories are shared by reference, so registrations are available to all
existing tab/modal contexts without copying or manual wiring.

## Development

```sh
swift build --build-tests
xcodebuild -scheme Orbit -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build-for-testing
```

These commands compile the library and tests without running them. Run
`swift test` or Xcode's test action when you explicitly want test execution.
The example is integration guidance; it is not a separate packaged app target.

## Status

Version 0.1.1 is an initial, pre-1.0 API. State/lifecycle tests are included;
visual behavior, gestures and mixed nested presentations still require device
or simulator validation before claiming production stability.
