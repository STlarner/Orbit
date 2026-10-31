import SwiftUI
import Testing

@testable import Orbit

@MainActor
@Suite("Orbit navigation")
struct OrbitTests {
    private func makeOrbit(tabs: [OrbitTab] = []) -> Orbit {
        let orbit = Orbit(tabs: tabs, diagnostics: .eventsOnly)
        orbit.register(TestRoute.self) { Text($0.value) }
        orbit.register(ContentRoute.self, navigation: .content) { _ in Text("Tabs") }
        return orbit
    }

    @Test("Registry and tab identity use types, not colliding display names")
    func typeIdentity() {
        let orbit = makeOrbit(tabs: [FirstTab(), SecondTab()])
        orbit.register(OtherRoute.self) { _ in Text("Other") }
        #expect(FirstTab() != SecondTab())
        #expect(orbit.tabs.tabs.count == 2)
        #expect(orbit.setRoot(OtherRoute()))
        #expect(orbit.rootContext.push(TestRoute()))
    }

    @Test("Route identity is per instance and duplicate instances are rejected")
    func routeIdentity() {
        let orbit = makeOrbit()
        orbit.setRoot(TestRoute())
        let first = TestRoute()
        let second = TestRoute()
        #expect(first != second)
        #expect(orbit.rootContext.push(first))
        #expect(!orbit.rootContext.push(first))
        #expect(orbit.rootContext.push(second))
        orbit.rootContext.popTo(first)
        #expect(orbit.rootContext.path == [first])
        orbit.rootContext.push(second)
        orbit.rootContext.popTo(TestRoute.self)
        #expect(orbit.rootContext.path == [first, second])
        orbit.rootContext.pop()
        orbit.rootContext.popToRoot()
        orbit.rootContext.pop()
        #expect(orbit.rootContext.path.isEmpty)
    }

    @Test("Tab contexts share late route registrations and independent paths")
    func tabsAndSharedRegistry() throws {
        let orbit = makeOrbit(tabs: [FirstTab(), SecondTab()])
        orbit.setRoot(ContentRoute())
        let first = try #require(orbit.tabs.context(for: FirstTab()))
        let second = try #require(orbit.tabs.context(for: SecondTab()))
        orbit.register(OtherRoute.self) { _ in Text("Late") }
        #expect(first.push(OtherRoute()))
        #expect(second.path.isEmpty)
        let route = TestRoute()
        #expect(orbit.tabs.navigate(to: SecondTab(), path: [route]))
        #expect(orbit.tabs.selectedTab == SecondTab())
        #expect(second.path == [route])
        #expect(first.path.count == 1)
        #expect(!orbit.rootContext.push(TestRoute()))
    }

    @Test("Modal opened from tab is owned and dismissed by the scene host")
    func tabPresentationOwnership() throws {
        let orbit = makeOrbit(tabs: [FirstTab()])
        orbit.setRoot(ContentRoute())
        let tab = try #require(orbit.tabs.context(for: FirstTab()))
        #expect(tab.present(TestRoute(), style: .sheet))
        let state = try #require(orbit.rootContext.presentation)
        #expect(state.context.presenter === orbit.rootContext)
        #expect(tab.presentation == nil)
        state.context.dismiss()
        #expect(!state.isPresented)
        // Context remains alive until SwiftUI's animation finishes.
        #expect(orbit.rootContext.presentation != nil)
        orbit.rootContext.completeDismiss(id: state.id)
        #expect(orbit.rootContext.presentation == nil)
        #expect(state.context.owner == nil)
    }

    @Test("Nested modals have independent owners and dismiss only their own flow")
    func nestedPresentations() throws {
        let orbit = makeOrbit()
        orbit.setRoot(TestRoute())
        orbit.rootContext.present(TestRoute(), style: .sheet)
        let first = try #require(orbit.rootContext.presentation)
        first.context.present(TestRoute(), style: .sheet)
        let second = try #require(first.context.presentation)
        second.context.dismiss()
        first.context.completeDismiss(id: second.id)
        #expect(first.context.presentation == nil)
        #expect(orbit.rootContext.presentation === first)
        first.context.present(TestRoute(), style: .sheet)
        let replacement = try #require(first.context.presentation)
        first.context.completeDismiss(id: second.id)
        #expect(first.context.presentation === replacement)
        orbit.dismissAll()
        orbit.rootContext.completeDismiss(id: first.id)
        #expect(replacement.context.owner == nil)
    }

    @Test("Interactive dismissal emits lifecycle events and clears the context")
    func interactiveDismissal() throws {
        let orbit = makeOrbit()
        var events: [OrbitEvent.Kind] = []
        orbit.onEvent = { events.append($0.kind) }
        orbit.rootContext.present(TestRoute(), style: .sheet)
        let state = try #require(orbit.rootContext.presentation)
        orbit.rootContext.requestDismiss(id: state.id)
        #expect(!orbit.rootContext.present(TestRoute(), style: .sheet))
        orbit.rootContext.completeDismiss(id: state.id)
        #expect(events == [.presented, .dismissalRequested, .rejected, .dismissed])
    }

    @Test("setRoot resets stacks but keeps the modal that replaces the root")
    func rootReplacement() throws {
        let orbit = makeOrbit(tabs: [FirstTab()])
        orbit.setRoot(ContentRoute())
        let tab = try #require(orbit.tabs.context(for: FirstTab()))
        tab.push(TestRoute())
        tab.present(TestRoute(), style: .sheet)
        let state = try #require(orbit.rootContext.presentation)
        state.context.setRoot(TestRoute())
        #expect(tab.path.isEmpty)
        #expect(orbit.rootRoute is TestRoute)
        #expect(orbit.rootContext.presentation === state)
        state.context.dismiss()
        orbit.rootContext.completeDismiss(id: state.id)
        #expect(orbit.rootContext.presentation == nil)
    }

    @Test("A closing ancestor rejects commands from descendant modal routers")
    func closingAncestor() throws {
        let orbit = makeOrbit()
        orbit.rootContext.present(TestRoute(), style: .sheet)
        let state = try #require(orbit.rootContext.presentation)
        state.context.present(TestRoute(), style: .sheet)
        let nested = try #require(state.context.presentation)
        orbit.dismissAll()
        #expect(!nested.context.push(TestRoute()))
        #expect(!nested.context.present(TestRoute(), style: .sheet))
        orbit.rootContext.completeDismiss(id: state.id)
    }

    @Test("Dismissal completion releases state before calling event consumers")
    func presentFromCompletion() throws {
        let orbit = makeOrbit()
        orbit.rootContext.present(TestRoute(), style: .sheet)
        let state = try #require(orbit.rootContext.presentation)
        let replacement = TestRoute()
        var accepted = false
        orbit.onEvent = { [weak orbit] event in
            if event.kind == .dismissed {
                accepted = orbit?.rootContext.present(replacement, style: .sheet) ?? false
            }
        }
        state.context.dismiss()
        orbit.rootContext.completeDismiss(id: state.id)
        #expect(accepted)
        #expect(orbit.rootContext.presentation?.route === replacement)
        orbit.rootContext.completeDismiss(id: state.id)
        #expect(orbit.rootContext.presentation?.route === replacement)
    }

    @Test("Rejected commands leave state unchanged and emit diagnostics")
    func validation() {
        let orbit = makeOrbit(tabs: [FirstTab(), FirstTab()])
        #expect(orbit.tabs.tabs.count == 1)
        #expect(!orbit.setRoot(UnregisteredRoute()))
        #expect(orbit.rootRoute == nil)
        #expect(!orbit.tabs.select(SecondTab()))
        #expect(orbit.tabs.selectedTab == FirstTab())
        #expect(!orbit.register(TestRoute.self) { _ in EmptyView() })
        #expect(!orbit.rootContext.present(UnregisteredRoute(), style: .sheet))
        #expect(orbit.rootContext.presentation == nil)
    }

    #if os(iOS)
    @Test("Full screens and sheets nest without sharing child state")
    func mixedPresentationStyles() throws {
        let orbit = makeOrbit()
        orbit.rootContext.present(TestRoute(), style: .fullScreen)
        let first = try #require(orbit.rootContext.presentation)
        first.context.present(TestRoute(), style: .sheet)
        let second = try #require(first.context.presentation)
        #expect(first.style == .fullScreen)
        #expect(second.style == .sheet)
        second.context.dismiss()
        first.context.completeDismiss(id: second.id)
        #expect(first.isPresented)
    }
    #endif
}

nonisolated private final class TestRoute: OrbitRoute {
    let value: String
    init(_ value: String = "Test") { self.value = value; super.init() }
    override class var routeName: String { "same-name" }
}
nonisolated private final class OtherRoute: OrbitRoute {
    override class var routeName: String { "same-name" }
}
nonisolated private final class ContentRoute: OrbitRoute {}
nonisolated private final class UnregisteredRoute: OrbitRoute {}
nonisolated private final class FirstTab: OrbitTab {
    override class var tabName: String { "same-tab-name" }
}
nonisolated private final class SecondTab: OrbitTab {
    override class var tabName: String { "same-tab-name" }
}
