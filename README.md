# Orbit

Orbit is a router for SwiftUI. It separates a screen from the destinations it
opens: the app registers route-to-view factories, and screens navigate with
`push`, `pop`, `present`, and `dismiss`.

The router owns navigation state for the window, including independent stacks
for tabs and modal flows. Destination views and their dependencies are built
by the registered factories.

## Installation

Add `https://github.com/STlarner/Orbit.git` as an Xcode package dependency
and select the `Orbit` product. For a SwiftPM project:

```swift
.package(url: "https://github.com/STlarner/Orbit.git", exact: "0.6.0")
```

Requires Swift 6.2+, iOS 17+ or macOS 14+.

## Quick start

The following steps build a small app with a home screen and a detail screen.

<!-- swift-example: quick-start -->

### 1. Define the routes

A route identifies a destination and carries the arguments it needs. Subclass
`OrbitRoute` for each screen you want to open:

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
```

### 2. Configure Orbit

Create an Orbit instance, register a view factory for each route, and select
the initial root. The detail factory receives the title stored in its route:

```swift
@MainActor
func makeOrbit() -> Orbit {
    let orbit = Orbit()
    orbit.register(HomeRoute.self) { _ in HomeView() }
    orbit.register(DetailRoute.self) { route in
        Text(route.title).navigationTitle(route.title)
    }
    orbit.setRoot(HomeRoute())
    return orbit
}
```

### 3. Install the root host

Keep the configured instance in your window's root view and pass it to
`OrbitRootHost`. The host displays the selected route and provides the router
to its screens through the SwiftUI environment:

```swift
@MainActor
struct AppWindow: View {
    @State private var orbit = makeOrbit()

    var body: some View { OrbitRootHost(orbit) }
}

@main
struct ExampleApp: App {
    var body: some Scene {
        WindowGroup { AppWindow() }
    }
}
```

Each window gets its own Orbit instance and navigation history.

### 4. Navigate from a screen

Read the environment router and push a route when the button is tapped:

```swift
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

<!-- /swift-example -->

## Navigation

Use the environment router from a screen:

| Command | Behavior |
|---|---|
| `push(route)` | Push a destination on the current stack. |
| `pop()` | Return to the previous screen. |
| `popToRoot()` | Return to the stack's root screen. |
| `popTo(RouteType.self)` / `popTo(route)` | Return to a pushed route type or instance. |
| `present(route, style: .sheet)` | Present a sheet with its own navigation flow. |
| `present(route, style: .fullScreen)` | Present a full-screen flow on iOS. |
| `dismiss()` | Close the current modal flow. |
| `setRoot(route)` | Replace the window's root. |
| `selectTab(tab, replacingPath:)` | Select a tab, optionally replacing its stack. |

The scene-owned `Orbit` also exposes root replacement, presentation, tab
selection, and `dismissAll`, for navigation initiated outside a screen.

## Tabs

Register a tabbed destination using the same `register` API. Each tab declares
its root content and label, and keeps its own stack when you switch tabs:

```swift
nonisolated final class TabsRoute: OrbitRoute {}
nonisolated final class HomeTab: OrbitTab {}
nonisolated final class TasksTab: OrbitTab {}

@MainActor
func configureTabs(in orbit: Orbit) {
    orbit.register(TabsRoute.self) { _ in
        OrbitTabView {
            OrbitTabItem(HomeTab()) {
                Text("Home")
            } label: {
                Label("Home", systemImage: "house")
            }

            OrbitTabItem(TasksTab()) {
                Text("Tasks")
            } label: {
                Label("Tasks", systemImage: "checklist")
            }
        }
    }
    orbit.setRoot(TabsRoute())
}
```

Call `configureTabs(in: orbit)` from the window's setup to use this root.
`selectTab(tab)` preserves the selected tab's history. Pass `replacingPath`
to replace it, or `[]` to open the tab's root screen.

## Deep links

Deep links are opt-in. Register a URL pattern only for destinations you want to
expose, after registering their view factory. Orbit matches normalized paths and
asks your resolver to build the route; URL parsing, scheme handling, dependency
resolution and logging stay in the application.

```swift
nonisolated final class DetailRoute: OrbitRoute {
    let title: String

    init(title: String) {
        self.title = title
        super.init()
    }
}

nonisolated final class DetailTab: OrbitTab {}

@MainActor
func registerDetailLinks(in orbit: Orbit) {
    orbit.register(DetailRoute.self) { route in
        Text(route.title)
    }
    orbit.registerDeepLink(
        DetailRoute.self,
        pattern: "detail/:id",
        tab: DetailTab()
    ) { parameters in
        guard let id = parameters["id"] else { return nil }
        return DetailRoute(title: id)
    }
}
```

Patterns are slash-separated. A segment beginning with `:` captures one path
component, which is percent-decoded before it reaches the resolver. Matching is
case-sensitive, the first registered pattern wins, and equivalent slash variants
such as `task/:id`, `/task/:id` and `task/:id/` are one registration.

`openDeepLink(path:)` resolves the route and applies the registered `tab` and
`presentation`. `resolveDeepLink(path:)` returns the route without navigating,
for applications that own placement:

```swift
struct DetailWindow: View {
    let orbit: Orbit

    var body: some View {
        OrbitRootHost(orbit)
            .onOpenURL { url in
                Task {
                    await orbit.openDeepLink(path: url.path)
                }
            }
    }
}
```

`openDeepLink` captures the root before awaiting, then verifies cancellation and
root identity before navigating. A stale request therefore cannot move the user
after the application replaced its root. Register only stable, shareable
destinations: their patterns become part of your public contract.

## Documentation and examples

- [API reference](https://stlarner.github.io/Orbit/api/)
- [Usage guide](https://stlarner.github.io/Orbit/api/documentation/orbit/usageguide):
  launch routing, modal flows, tab decoration, events, and deep links.
- [OrbitDemo.swift](Examples/OrbitDemo.swift): a tabbed root, modal tabs, and
  push navigation.
