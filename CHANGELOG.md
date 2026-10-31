# Changelog

## 0.1.1

- Release modal state before emitting completed-dismissal callbacks, allowing
  consumers to immediately request the next presentation.
- Reject presentation and push commands from flows whose modal ancestor is
  closing, and ignore stale/unsolicited completion callbacks.
- Add regression tests for both lifecycle cases.

## 0.1.0

- Initial dependency-free Swift 6 navigation package.
- Scene root host, imperative context routers and shared typed route registry.
- Independent tab stacks and synchronous tab/path navigation.
- Sheet/full-screen presentation style and independent nested modal contexts.
- Identity-safe dismissal cleanup and interactive navigation events.
- Optional diagnostics callback with no logger or DI dependency.
- Swift Testing coverage, build-only CI and a SwiftUI integration example.
