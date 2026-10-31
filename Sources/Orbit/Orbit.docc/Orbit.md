# ``Orbit``

Imperative SwiftUI navigation with declared destinations and independent tab flows.

## Overview

This reference is generated from the repository's `main` branch. For a released
API, consult its version tag. Read <doc:UsageGuide> for setup and navigation examples.

An ``Orbit`` instance holds a window's navigation state and destination
factories. ``OrbitRootHost`` renders its root and modal flows. Screens receive
an ``OrbitRouter`` through `@Environment(\.orbit)` to push, pop, select tabs,
present a flow, or replace the root.

``OrbitTabView`` declares an independent tab flow using ``OrbitTabItem`` content
and labels. Native ModifiedContent chains retain ``OrbitTabFlow`` metadata;
`wrapped` preserves it through Group, AnyView, and custom decoration. The
registered flow retains both its tab declaration and decorated rendering.

Commands and factories run on the main actor. A returned success reports that
the state request was accepted; SwiftUI performs the visual transition afterward.

API symbol pages describe scopes, defaults, validation and event timing.

## Topics

### Usage

- <doc:UsageGuide>

### Scene ownership and rendering

- ``Orbit``
- ``OrbitRootHost``

### Destination commands

- ``OrbitRouter``
- ``OrbitRoute``
- ``SwiftUICore/EnvironmentValues/orbit``

### Declaring tab flows

- ``OrbitTabView``
- ``OrbitTabFlow``
- ``OrbitWrappedTabFlow``
- ``OrbitTabItem``
- ``OrbitTab``
- ``OrbitTabBuilder``
- ``OrbitTabBarVisibility``

### Presentation and stack policies

- ``OrbitPresentationStyle``
- ``OrbitNavigationMode``

### Observing and validating navigation

- ``OrbitEvent``
- ``OrbitDiagnostics``

Events are delivered after the command's full state mutation. Further commands
from a callback are supported; their events follow the original batch without
recursive observer calls. Snapshots describe their originating operations,
while live navigation state may have been changed by another callback.
