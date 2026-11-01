# Using Orbit

Configure destinations, navigate from screens, and coordinate tab and modal flows.

## Route registration

A route stores the arguments needed to build a destination. Register a factory
for its exact type, then pass route instances to the router. The factory is the
composition point for ViewModels and other application dependencies.

```swift
nonisolated final class RoomRoute: OrbitRoute {
    let roomID: String

    init(roomID: String) {
        self.roomID = roomID
        super.init()
    }
}

@MainActor
func registerRooms(in orbit: Orbit) {
    orbit.register(RoomRoute.self) { route in
        Text("Room: \(route.roomID)")
    }
}
```

Registration retains the factory. Ordinary factories run during SwiftUI
rendering and may be evaluated repeatedly. Tab-declaration factories run when
their root or modal is prepared; individual tab content and label factories
remain lazy. Keep one-time work in a ViewModel or the screen's `.task`.

Routes compare by instance identity. Use a fresh instance for each new stack
entry and root replacement. Reusing a root instance resets paths but keeps the
same SwiftUI root identifier, which may retain local view state. Route names
are diagnostic labels; the registry and typed `popTo` use exact Swift types.

## The root host

Create an ``Orbit`` for each window and install one ``OrbitRootHost`` for it.
The host displays ``Orbit/rootRoute``, provides the environment router, and
retains the presentation host across root changes.

For asynchronous launch decisions, supply placeholder content. It receives the
root router and can select a registered root when launch work completes. The
placeholder is not automatically wrapped in a navigation stack.

By default, an ordinary root or modal starts an Orbit-managed stack. A route
registered with `.content` renders directly, which is useful for a custom
non-stack flow. A recognized tab flow starts its own tab stacks.

## Navigation from screens

Read ``OrbitRouter`` with `@Environment(\.orbit)`. `push`, `pop`, and `popTo`
operate on that screen's stack. `popToRoot` clears pushed entries; `dismiss`
closes the enclosing modal flow. These are different operations.

`popTo` searches pushed entries, keeps the matching entry, and removes entries
after it. The type overload matches the last occurrence of an exact type; the
instance overload matches a reference. The stack root is not a pushed entry.

The owner is main-actor isolated. Commands update state synchronously and return
acceptance, while SwiftUI handles the transition. An accepted `present` is a
request, not an acknowledgement that its view is already visible.

## Tab flows

``OrbitTabView`` declares ordered ``OrbitTabItem`` values. Each tab gets its own
stack and a router that selects the nearest tab container. A modal tab flow has
independent state, including when it uses the same tab types as the root.

Tab keys compare by exact type. New instances of the same subclass select the
same tab. The declaration is fixed for a flow's lifetime; start another root
or modal to change the tab configuration. Conditions and loops can be used in
the declaration builder. Empty declarations and duplicate types are rejected
before replacing a recognized flow.

Use `selectTab(tab)` to preserve history. An array passed as `replacingPath`
replaces the entire selected tab stack; `[]` opens its root screen. Other tabs'
histories are unchanged. Validation checks the tab and replacement before
applying either change.

Tab flows are root or modal destinations. A registered independent tab flow
cannot be a pushed entry. A normal SwiftUI TabView that groups content can
still be part of an ordinary screen.

## Tab decoration

Native SwiftUI ModifiedContent chains preserve ``OrbitTabFlow`` metadata.
Orbit prepares both the original declaration and the complete decorated view,
so styling is retained when the flow is rendered.

Use `wrapped` on the source flow when a transformation hides its metadata,
such as AnyView, Group, or an arbitrary container:

```swift
@MainActor
func decorateTabs(_ tabs: OrbitTabView) -> some View {
    tabs.wrapped { content in
        AnyView(Group { content }.padding().background(.thinMaterial))
    }
}
```

Include the supplied flow exactly once. For a reusable wrapper, expose the
same stored declaration that its body renders:

```swift
@MainActor
struct TabsPanel: OrbitTabFlow {
    let orbitTabView: OrbitTabView

    var body: some View {
        Group { orbitTabView }.padding()
    }
}
```

The metadata getter should return a stored value, preserving its identity.
Orbit does not evaluate a custom wrapper's body during registration. A raw
opaque wrapper that discards metadata cannot be identified as a tab flow;
use `wrapped` or a conformance to keep the declaration available.

The `.automatic`, `.visible`, and `.hiddenOnPush` policies control iOS tab-bar
appearance. They leave path and selection semantics unchanged. Destination
content can also use native SwiftUI toolbar preferences.

## Modal ownership

The first modal is hosted outside its enclosing tab container. Each next modal
is hosted by its predecessor. A modal has its own path or tab state and receives
a router for that flow.

Calling `dismiss` from a modal tab closes the containing modal. Dismissing a
nested modal leaves its parent open. `Orbit.dismissAll()` closes the complete
modal chain while retaining the root's navigation paths.

Replacing the root retires its old stack and tabs, but preserves active modals.
Onboarding can therefore select Home behind its cover and then dismiss itself.
Independent modal tabs retain their own selection and history.

SwiftUI dismissal bindings and `onDismiss` synchronize programmatic and
interactive closing. State remains alive during the close animation and is
released on completion. Descendants are invalidated with their parent; they do
not each emit a separate `.dismissed` event. Requests targeting a closing modal
chain are rejected rather than queued.

## Events and diagnostics

``Orbit/onNavigationEvent`` receives ``OrbitEvent`` values on the main actor.
The callback observes accepted operations and reported rejections. Configure
it to send events to your application's logger or analytics:

```swift
@MainActor
func observeNavigation(in orbit: Orbit) {
    orbit.onNavigationEvent = { event in
        print(event.kind, event.routeName ?? "", event.path, event.message)
    }
}
```

A command finishes its state changes before delivering its event batch. A
callback may issue another command; its state changes complete immediately,
while its events follow the current batch in FIFO order. Observer calls are
not recursive within that owner. Avoid event/command feedback loops.

Events are immutable operation snapshots. Live state may differ after another
callback changes it. `.presented` means a modal request was accepted, while
`.dismissed` follows cleanup. Event paths exclude the root; a tab-selection
event refers to its containing flow, not the selected tab's path.

Default diagnostics record a rejected operation and assert in debug. Release
builds return rejection. `.eventsOnly` records rejections without asserting,
which supports consumer-owned recovery. A debug assertion in an observer can
stop delivery of its pending events. Events use diagnostic names and messages,
not localized user-facing error strings or a persistent error-code contract.

## Deep links

Deep-link support is opt-in. Register a URL pattern only for destinations whose
URL is a stable, shareable contract. The route must already be registered with
``Orbit/register(_:navigation:factory:)``; then
``Orbit/registerDeepLink(_:pattern:tab:presentation:resolve:)`` maps a normalized
path to that route. ``Orbit/registerDeepLinkTab(_:pattern:)`` maps a path that is
just a tab root. URL parsing, scheme handling, dependency resolution and logging
stay in the application.

Patterns are slash-separated. A segment beginning with `:` captures one path
component, which is percent-decoded before it reaches the resolver. Matching is
case-sensitive, the first registered pattern wins, and equivalent slash variants
such as `task/:id`, `/task/:id` and `task/:id/` are one registration.

```swift
nonisolated final class TaskRoute: OrbitRoute {
    let taskID: String

    init(taskID: String) {
        self.taskID = taskID
        super.init()
    }
}

nonisolated final class TasksTab: OrbitTab {}

@MainActor
func registerTaskLinks(in orbit: Orbit) {
    orbit.register(TaskRoute.self) { route in
        Text(route.taskID)
    }
    orbit.registerDeepLinkTab(TasksTab(), pattern: "tasks")
    orbit.registerDeepLink(
        TaskRoute.self,
        pattern: "task/:id",
        tab: TasksTab()
    ) { parameters in
        guard let id = parameters["id"] else { return nil }
        return TaskRoute(taskID: id)
    }
}
```

The resolver may await application work such as loading an entity, and returns
`nil` when the destination is unavailable. ``Orbit/openDeepLink(path:)`` resolves
the route and applies the registered tab and presentation. If the resolver
returns `nil`, the registered tab root is selected; without a tab, navigation is
unchanged. ``Orbit/resolveDeepLink(path:)`` returns a route without navigating
when the application owns placement, and `nil` for tab-only paths.

`openDeepLink` captures the root before awaiting, then verifies cancellation and
root identity before navigating, so a stale request cannot move the user after
the application replaced its root. Cancel obsolete requests when a newer one
arrives. Whether a deep link should close a modal first is application policy.
A router is stack/flow-scoped, so retaining it does not cancel work belonging to
an individual popped screen.

## Previews and validation

Standalone screens can receive a custom ``OrbitRouter`` through the environment
for previews or tests. OrbitRootHost installs its own routers internally;
place screen-specific overrides on destination content.

The package's model tests cover identity, validation, path updates, scoped tabs,
and dismissal state. Visual transitions, gestures, and modal mounting depend on
SwiftUI and should also be checked on the OS versions supported by your app.
