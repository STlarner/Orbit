# Orbit

Orbit is a router for SwiftUI. It separates a screen from the destinations it
opens: the app registers route-to-view factories, and screens navigate with
`push`, `pop`, `present`, and `dismiss`.

The router owns navigation state for the window, including independent stacks
for tabs and modal flows. Destination views and their dependencies are built
by the registered factories.

## Quick start

Define your routes, register their destinations, and install `OrbitRootHost`
in the window's root view:

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
        WindowGroup { AppWindow() }
    }
}

@MainActor
struct AppWindow: View {
    @State private var orbit: Orbit

    init() {
        let orbit = Orbit()
        orbit.register(HomeRoute.self) { _ in HomeView() }
        orbit.register(DetailRoute.self) { route in
            Text(route.title).navigationTitle(route.title)
        }
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

`HomeView` knows the route it wants to open. The factory decides which view
to create and can supply its ViewModel or other dependencies. Orbit provides
the navigation stack and back navigation.

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
        OrbitTabView(tabBarVisibility: .hiddenOnPush) {
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

The tab bar uses SwiftUI's automatic visibility by default. `.hiddenOnPush`
hides it while the tab has pushed screens; `.visible` keeps it visible.
Tab flows can also be presented as modals with their own selection and history.

## Installation

Add `https://github.com/STlarner/Orbit.git` as an Xcode package dependency
and select the `Orbit` product. For a SwiftPM project:

```swift
.package(url: "https://github.com/STlarner/Orbit.git", exact: "0.5.0")
```

Requires Swift 6.2+, iOS 17+ or macOS 14+. Full-screen covers and tab-bar
visibility policies are available on iOS.

## Documentation and examples

- [API reference](https://stlarner.github.io/Orbit/api/)
- [Usage guide](https://stlarner.github.io/Orbit/api/documentation/orbit/usageguide):
  launch routing, modal flows, tab decoration, events, and deep links.
- [OrbitDemo.swift](Examples/OrbitDemo.swift): a tabbed root, modal tabs, and
  push navigation.
