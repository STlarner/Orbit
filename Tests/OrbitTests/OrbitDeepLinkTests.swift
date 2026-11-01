import SwiftUI
import Testing

@testable import Orbit

@MainActor
@Suite("Orbit deep links")
struct OrbitDeepLinkTests {
    private func makeOrbit() -> Orbit {
        let orbit = Orbit(diagnostics: .eventsOnly)
        orbit.register(TabsRoute.self) { _ in
            OrbitTabView {
                OrbitTabItem(HomeTab()) { Text("Home") } label: { Text("Home") }
                OrbitTabItem(TasksTab()) { Text("Tasks") } label: { Text("Tasks") }
            }
        }
        orbit.register(TaskRoute.self) { _ in Text("Task") }
        orbit.register(RoomRoute.self) { _ in Text("Room") }
        orbit.register(ModalRoute.self) { _ in Text("Modal") }
        orbit.setRoot(TabsRoute())
        return orbit
    }

    private func registerTaskLink(in orbit: Orbit) {
        orbit.registerDeepLink(
            TaskRoute.self,
            pattern: "task/:id",
            tab: TasksTab()
        ) { parameters in
            guard let id = parameters["id"] else { return nil }
            return TaskRoute(identifier: id)
        }
    }

    @Test("Resolving captures path parameters without navigating")
    func resolveCapturesParameters() async throws {
        let orbit = makeOrbit()
        registerTaskLink(in: orbit)

        let route = try #require(
            await orbit.resolveDeepLink(path: "task/42") as? TaskRoute
        )
        #expect(route.identifier == "42")
        #expect(orbit.rootContext.tabManager?.selectedTab == HomeTab())
        #expect(orbit.rootContext.tabManager?.context(for: TasksTab())?.path.isEmpty == true)
    }

    @Test("Patterns normalize slashes and percent-decode captured values")
    func normalizesAndDecodes() async throws {
        let orbit = makeOrbit()
        orbit.registerDeepLink(
            RoomRoute.self,
            pattern: "room/:id",
            tab: HomeTab()
        ) { parameters in
            guard let id = parameters["id"] else { return nil }
            return RoomRoute(identifier: id)
        }

        let route = try #require(
            await orbit.resolveDeepLink(path: "/room/a%20b/") as? RoomRoute
        )
        #expect(route.identifier == "a b")
    }

    @Test("Unknown paths resolve and open without changing navigation")
    func unknownPath() async {
        let orbit = makeOrbit()
        #expect(await orbit.resolveDeepLink(path: "missing") == nil)
        #expect(!(await orbit.openDeepLink(path: "missing")))
        #expect(orbit.rootContext.tabManager?.selectedTab == HomeTab())
    }

    @Test("Opening selects the registered tab and replaces its path")
    func openSelectsTabAndReplacesPath() async throws {
        let orbit = makeOrbit()
        registerTaskLink(in: orbit)

        #expect(await orbit.openDeepLink(path: "task/42"))
        let tabs = try #require(orbit.rootContext.tabManager)
        #expect(tabs.selectedTab == TasksTab())
        let path = try #require(tabs.context(for: TasksTab())?.path)
        #expect(path.count == 1)
        #expect((path.first as? TaskRoute)?.identifier == "42")
    }

    @Test("Opening without a tab pushes onto the current tab")
    func openWithoutTabUsesCurrentTab() async throws {
        let orbit = makeOrbit()
        orbit.registerDeepLink(
            TaskRoute.self,
            pattern: "task/:id"
        ) { parameters in
            guard let id = parameters["id"] else { return nil }
            return TaskRoute(identifier: id)
        }

        #expect(await orbit.openDeepLink(path: "task/42"))
        let tabs = try #require(orbit.rootContext.tabManager)
        #expect(tabs.selectedTab == HomeTab())
        #expect(tabs.context(for: HomeTab())?.path.count == 1)
    }

    @Test("A registered presentation is applied above the selected tab")
    func openPresentsRoute() async throws {
        let orbit = makeOrbit()
        var resolved: TaskRoute?
        orbit.registerDeepLink(
            TaskRoute.self,
            pattern: "task/:id",
            tab: TasksTab(),
            presentation: .sheet
        ) { parameters in
            guard let id = parameters["id"] else { return nil }
            let route = TaskRoute(identifier: id)
            resolved = route
            return route
        }

        #expect(await orbit.openDeepLink(path: "task/42"))
        let state = try #require(orbit.rootContext.presentation)
        #expect(state.route === resolved)
        #expect(state.style == .sheet)
        let tabs = try #require(orbit.rootContext.tabManager)
        #expect(tabs.selectedTab == TasksTab())
        #expect(tabs.context(for: TasksTab())?.path.isEmpty == true)
    }

    @Test("An unavailable destination leaves navigation unchanged")
    func unresolvedDestination() async throws {
        let orbit = makeOrbit()
        orbit.registerDeepLink(
            TaskRoute.self,
            pattern: "task/:id",
            tab: TasksTab()
        ) { _ in nil }

        #expect(!(await orbit.openDeepLink(path: "task/42")))
        let tabs = try #require(orbit.rootContext.tabManager)
        #expect(tabs.selectedTab == HomeTab())
        #expect(tabs.context(for: TasksTab())?.path.isEmpty == true)
        #expect(orbit.rootContext.presentation == nil)
    }

    @Test("Deep links require an already registered route")
    func unregisteredRoute() {
        let orbit = makeOrbit()
        #expect(
            !orbit.registerDeepLink(
                UnregisteredRoute.self,
                pattern: "missing"
            ) { _ in UnregisteredRoute() }
        )
    }

    @Test("Invalid and duplicate patterns are rejected")
    func invalidPatterns() {
        let orbit = makeOrbit()
        #expect(
            !orbit.registerDeepLink(
                TaskRoute.self,
                pattern: ""
            ) { _ in nil }
        )
        #expect(
            !orbit.registerDeepLink(
                TaskRoute.self,
                pattern: "task/:"
            ) { _ in nil }
        )
        #expect(
            !orbit.registerDeepLink(
                TaskRoute.self,
                pattern: "task/:id/:id"
            ) { _ in nil }
        )

        registerTaskLink(in: orbit)
        #expect(
            !orbit.registerDeepLink(
                TaskRoute.self,
                pattern: "/task/:id/"
            ) { _ in TaskRoute(identifier: "duplicate") }
        )
    }

    @Test("The first registered matching pattern wins")
    func firstMatchWins() async throws {
        let orbit = makeOrbit()
        orbit.registerDeepLink(
            TaskRoute.self,
            pattern: "task/:id",
            tab: TasksTab()
        ) { parameters in
            guard let id = parameters["id"] else { return nil }
            return TaskRoute(identifier: id)
        }
        orbit.registerDeepLink(
            TaskRoute.self,
            pattern: "task/new",
            tab: TasksTab()
        ) { _ in TaskRoute(identifier: "literal") }

        let route = try #require(
            await orbit.resolveDeepLink(path: "task/new") as? TaskRoute
        )
        #expect(route.identifier == "new")
    }

    @Test("Root replacement prevents a resolved link from navigating")
    func rootReplacementPreventsNavigation() async throws {
        let orbit = makeOrbit()
        var didStart = false
        var started: CheckedContinuation<Void, Never>?
        var release: CheckedContinuation<Void, Never>?
        orbit.registerDeepLink(
            TaskRoute.self,
            pattern: "task/:id",
            tab: TasksTab()
        ) { parameters in
            await withCheckedContinuation { continuation in
                release = continuation
                didStart = true
                started?.resume()
                started = nil
            }
            guard let id = parameters["id"] else { return nil }
            return TaskRoute(identifier: id)
        }

        let request = Task { await orbit.openDeepLink(path: "task/42") }
        await withCheckedContinuation { continuation in
            if didStart {
                continuation.resume()
            } else {
                started = continuation
            }
        }
        let replacement = RoomRoute(identifier: "replacement")
        orbit.setRoot(replacement)
        release?.resume()

        #expect(await request.value == false)
        #expect(orbit.rootRoute === replacement)
        #expect(orbit.rootContext.tabManager == nil)
    }

    @Test("Cancellation prevents a resolved link from navigating")
    func cancellationPreventsNavigation() async throws {
        let orbit = makeOrbit()
        var didStart = false
        var started: CheckedContinuation<Void, Never>?
        var release: CheckedContinuation<Void, Never>?
        orbit.registerDeepLink(
            TaskRoute.self,
            pattern: "task/:id",
            tab: TasksTab()
        ) { parameters in
            await withCheckedContinuation { continuation in
                release = continuation
                didStart = true
                started?.resume()
                started = nil
            }
            guard let id = parameters["id"] else { return nil }
            return TaskRoute(identifier: id)
        }

        let request = Task { await orbit.openDeepLink(path: "task/42") }
        await withCheckedContinuation { continuation in
            if didStart {
                continuation.resume()
            } else {
                started = continuation
            }
        }
        request.cancel()
        release?.resume()

        #expect(await request.value == false)
        let tabs = try #require(orbit.rootContext.tabManager)
        #expect(tabs.selectedTab == HomeTab())
        #expect(tabs.context(for: TasksTab())?.path.isEmpty == true)
    }

    #if os(macOS)
        @Test("Full-screen deep-link presentations are rejected on macOS")
        func fullScreenRejected() {
            let orbit = makeOrbit()
            #expect(
                !orbit.registerDeepLink(
                    TaskRoute.self,
                    pattern: "task/:id",
                    tab: TasksTab(),
                    presentation: .fullScreen
                ) { _ in TaskRoute(identifier: "42") }
            )
        }
    #endif
}

nonisolated private final class TaskRoute: OrbitRoute {
    let identifier: String

    init(identifier: String) {
        self.identifier = identifier
        super.init()
    }
}

nonisolated private final class RoomRoute: OrbitRoute {
    let identifier: String

    init(identifier: String) {
        self.identifier = identifier
        super.init()
    }
}

nonisolated private final class ModalRoute: OrbitRoute {}
nonisolated private final class TabsRoute: OrbitRoute {}
nonisolated private final class UnregisteredRoute: OrbitRoute {}
nonisolated private final class HomeTab: OrbitTab {}
nonisolated private final class TasksTab: OrbitTab {}
