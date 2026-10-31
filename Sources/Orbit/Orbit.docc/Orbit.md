# ``Orbit``

Imperative SwiftUI navigation with declared destinations and independent tab flows.

## Overview

Create an ``Orbit`` owner per window, register destination factories, then
display them with ``OrbitRootHost``. Screens use an ``OrbitRouter`` through
`@Environment(\.orbit)`; no view assembles navigation paths or stack hosts.

A factory returning ``OrbitTabView`` starts an independent root/modal tab flow.
Declare its content and label with ``OrbitTabItem``. Registered tab flows cannot
be pushed inside another independent stack. Native ModifiedContent chains retain
``OrbitTabFlow`` metadata automatically. For Group, AnyView and custom decoration,
use `wrapped` or conform a wrapper to OrbitTabFlow; private SwiftUI storage is
never inspected and the complete decorated content is retained for rendering.

Commands and factories are main-actor isolated. Returned success means a state
request was accepted, not that UIKit completed an animation. Preserve one owner
per window and cancel obsolete async work in your application before navigating.

The repository README contains quick-start, DI, deep-link and limitation guidance.
API symbol pages describe scopes, defaults, validation and event timing.

## Topics

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
