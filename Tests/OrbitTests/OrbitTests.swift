import SwiftUI
import Testing

@testable import Orbit

@MainActor
@Suite("Orbit navigation")
struct OrbitTests {
    private func makeOrbit(tabs: [OrbitTab] = []) -> Orbit {
        let orbit = Orbit(diagnostics: .eventsOnly)
        orbit.register(TestRoute.self) { Text($0.value) }
        orbit.register(ContentRoute.self, navigation: .content) { _ in Text("Content") }
        orbit.registerTabs(TabsRoute.self) { _ in
            OrbitTabView {
                for tab in tabs {
                    OrbitTabItem(tab) { Text(tab.name) } label: { Text(tab.name) }
                }
            }
        }
        if !tabs.isEmpty { orbit.setRoot(TabsRoute()) }
        return orbit
    }

    @Test("Registry and tab identity use types, not colliding display names")
    func typeIdentity() throws {
        let orbit = makeOrbit(tabs: [FirstTab(), SecondTab()])
        let tabs = try #require(orbit.rootContext.tabManager)
        orbit.register(OtherRoute.self) { _ in Text("Other") }
        #expect(FirstTab() != SecondTab())
        #expect(tabs.tabs.count == 2)
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

    @Test("Tab declarations are ready before root events, without rendering screens")
    func preparationBeforeRendering() throws {
        let orbit = makeOrbit()
        var contentCreations = 0
        var selectedFromEvent = false
        orbit.registerTabs(ModalTabsRoute.self) { _ in
            OrbitTabView {
                OrbitTabItem(FirstTab()) {
                    contentCreations += 1
                    return Text("First")
                } label: { Text("First") }
                OrbitTabItem(SecondTab()) { Text("Second") } label: { Text("Second") }
            }
        }
        orbit.onNavigationEvent = { [weak orbit] event in
            if event.kind == .rootChanged {
                selectedFromEvent = orbit?.selectTab(SecondTab()) ?? false
            }
        }
        #expect(orbit.setRoot(ModalTabsRoute()))
        #expect(contentCreations == 0)
        #expect(selectedFromEvent)
        let tabs = try #require(orbit.rootContext.tabManager)
        #expect(tabs.selectedTab == SecondTab())
    }

    @Test("Tab contexts share late route registrations and independent paths")
    func tabsAndSharedRegistry() throws {
        let orbit = makeOrbit(tabs: [FirstTab(), SecondTab()])
        let tabs = try #require(orbit.rootContext.tabManager)
        let first = try #require(tabs.context(for: FirstTab()))
        let second = try #require(tabs.context(for: SecondTab()))
        orbit.register(OtherRoute.self) { _ in Text("Late") }
        #expect(first.push(OtherRoute()))
        #expect(second.path.isEmpty)
        let route = TestRoute()
        #expect(orbit.selectTab(SecondTab(), replacingPath: [route]))
        #expect(tabs.selectedTab == SecondTab())
        #expect(second.path == [route])
        #expect(first.path.count == 1)
        #expect(!orbit.rootContext.push(TestRoute()))
    }

    @Test("Selecting a tab preserves its path unless explicitly replaced")
    func selectionPathPolicy() throws {
        let orbit = makeOrbit(tabs: [FirstTab(), SecondTab()])
        let tabs = try #require(orbit.rootContext.tabManager)
        let first = try #require(tabs.context(for: FirstTab()))
        let second = try #require(tabs.context(for: SecondTab()))
        let firstRoute = TestRoute("First")
        let secondRoute = TestRoute("Second")
        first.push(firstRoute)
        second.push(secondRoute)
        #expect(orbit.selectTab(SecondTab()))
        #expect(second.path == [secondRoute])
        #expect(orbit.selectTab(FirstTab(), replacingPath: nil))
        #expect(first.path == [firstRoute])
        #expect(orbit.selectTab(SecondTab(), replacingPath: []))
        #expect(second.path.isEmpty)
        #expect(first.path == [firstRoute])
        #expect(tabs.selectedTab == SecondTab())
    }

    @Test("The environment router forwards tab selection and optional path")
    func routerTabSelection() throws {
        let orbit = makeOrbit(tabs: [FirstTab(), SecondTab()])
        let router: any OrbitRouter = orbit.rootContext
        let tabs = try #require(orbit.rootContext.tabManager)
        let route = TestRoute()
        #expect(router.selectTab(SecondTab(), replacingPath: [route]))
        let second = try #require(tabs.context(for: SecondTab()))
        #expect(tabs.selectedTab == SecondTab())
        #expect(second.path == [route])
        #expect(router.selectTab(FirstTab()))
        #expect(second.path == [route])
    }

    @Test("Rejected replacement paths do not change either stack or selection")
    func invalidSelectionPath() throws {
        let orbit = makeOrbit(tabs: [FirstTab(), SecondTab()])
        let tabs = try #require(orbit.rootContext.tabManager)
        let second = try #require(tabs.context(for: SecondTab()))
        let route = TestRoute()
        second.push(route)
        #expect(!orbit.selectTab(SecondTab(), replacingPath: [UnregisteredRoute()]))
        #expect(!orbit.selectTab(SecondTab(), replacingPath: [route, route]))
        #expect(!orbit.selectTab(SecondTab(), replacingPath: [TabsRoute()]))
        #expect(tabs.selectedTab == FirstTab())
        #expect(second.path == [route])
    }

    @Test("Tab flows are root or modal destinations, never pushed stacks")
    func tabFlowPushRejected() {
        let orbit = makeOrbit(tabs: [FirstTab()])
        orbit.setRoot(TestRoute())
        #expect(!orbit.rootContext.push(TabsRoute()))
        #expect(orbit.rootContext.path.isEmpty)
        #expect(orbit.present(TabsRoute()))
        #expect(orbit.rootContext.presentation?.context.tabManager != nil)
    }

    @Test("Modal opened from tab is owned and dismissed by its flow host")
    func tabPresentationOwnership() throws {
        let orbit = makeOrbit(tabs: [FirstTab()])
        let tabs = try #require(orbit.rootContext.tabManager)
        let tab = try #require(tabs.context(for: FirstTab()))
        #expect(tab.present(TestRoute(), style: .sheet))
        let state = try #require(orbit.rootContext.presentation)
        #expect(state.context.presenter === orbit.rootContext)
        #expect(tab.presentation == nil)
        state.context.dismiss()
        #expect(!state.isPresented)
        #expect(orbit.rootContext.presentation != nil)
        orbit.rootContext.completeDismiss(id: state.id)
        #expect(orbit.rootContext.presentation == nil)
        #expect(state.context.owner == nil)
    }

    @Test("Root and modal tab containers have independent state and routing scope")
    func independentModalTabs() throws {
        let orbit = makeOrbit(tabs: [FirstTab(), SecondTab()])
        orbit.registerTabs(ModalTabsRoute.self) { _ in
            OrbitTabView {
                OrbitTabItem(FirstTab()) { Text("Modal first") } label: { Text("First") }
                OrbitTabItem(SecondTab()) { Text("Modal second") } label: { Text("Second") }
            }
        }
        let rootTabs = try #require(orbit.rootContext.tabManager)
        let rootRoute = TestRoute("Root")
        orbit.selectTab(SecondTab(), replacingPath: [rootRoute])
        orbit.present(ModalTabsRoute())
        let modal = try #require(orbit.rootContext.presentation)
        let modalTabs = try #require(modal.context.tabManager)
        #expect(modalTabs.selectedTab == FirstTab())
        let modalRoute = TestRoute("Modal")
        modal.context.selectTab(SecondTab(), replacingPath: [modalRoute])
        #expect(modalTabs.context(for: SecondTab())?.path == [modalRoute])
        #expect(rootTabs.context(for: SecondTab())?.path == [rootRoute])

        let modalTab = try #require(modalTabs.context(for: SecondTab()))
        modalTab.present(TestRoute(), style: .sheet)
        let nested = try #require(modal.context.presentation)
        #expect(nested.context.presenter === modal.context)
        nested.context.selectTab(FirstTab())
        #expect(modalTabs.selectedTab == FirstTab())
        #expect(rootTabs.selectedTab == SecondTab())
        nested.context.dismiss()
        modal.context.completeDismiss(id: nested.id)
        #expect(orbit.rootContext.presentation === modal)
    }

    @Test("Nested modals have independent owners and dismiss their own flow")
    func nestedPresentations() throws {
        let orbit = makeOrbit()
        orbit.setRoot(TestRoute())
        orbit.present(TestRoute())
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
        orbit.onNavigationEvent = { events.append($0.kind) }
        orbit.present(TestRoute())
        let state = try #require(orbit.rootContext.presentation)
        orbit.rootContext.requestDismiss(id: state.id)
        #expect(!orbit.present(TestRoute()))
        orbit.rootContext.completeDismiss(id: state.id)
        #expect(events == [.presented, .dismissalRequested, .rejected, .dismissed])
    }

    @Test("setRoot retires old tab stacks but preserves presented tab flows")
    func rootReplacement() throws {
        let orbit = makeOrbit(tabs: [FirstTab()])
        let oldTabs = try #require(orbit.rootContext.tabManager)
        let tab = try #require(oldTabs.context(for: FirstTab()))
        tab.push(TestRoute())
        tab.present(TabsRoute(), style: .sheet)
        let state = try #require(orbit.rootContext.presentation)
        let modalTabs = try #require(state.context.tabManager)
        state.context.setRoot(TestRoute())
        #expect(tab.path.isEmpty)
        #expect(tab.owner == nil)
        #expect(!tab.push(TestRoute()))
        #expect(orbit.rootContext.tabManager == nil)
        #expect(state.context.tabManager === modalTabs)
        #expect(state.context.selectTab(FirstTab()))
        #expect(orbit.rootContext.presentation === state)
        state.context.dismiss()
        orbit.rootContext.completeDismiss(id: state.id)
        #expect(modalTabs.contexts[FirstTab()]?.owner == nil)
        #expect(orbit.rootContext.presentation == nil)
    }

    @Test("A closing ancestor rejects commands from descendant modal routers")
    func closingAncestor() throws {
        let orbit = makeOrbit(tabs: [FirstTab()])
        orbit.present(TabsRoute())
        let state = try #require(orbit.rootContext.presentation)
        let modalTabs = try #require(state.context.tabManager)
        let tab = try #require(modalTabs.context(for: FirstTab()))
        tab.present(TestRoute(), style: .sheet)
        let nested = try #require(state.context.presentation)
        orbit.dismissAll()
        #expect(!nested.context.push(TestRoute()))
        #expect(!nested.context.present(TestRoute(), style: .sheet))
        #expect(!tab.selectTab(FirstTab()))
        orbit.rootContext.completeDismiss(id: state.id)
    }

    @Test("Dismissal completion releases state before calling event consumers")
    func presentFromCompletion() throws {
        let orbit = makeOrbit()
        orbit.present(TestRoute())
        let state = try #require(orbit.rootContext.presentation)
        let replacement = TestRoute()
        var accepted = false
        orbit.onNavigationEvent = { [weak orbit] event in
            if event.kind == .dismissed {
                accepted = orbit?.present(replacement) ?? false
            }
        }
        state.context.dismiss()
        orbit.rootContext.completeDismiss(id: state.id)
        #expect(accepted)
        #expect(orbit.rootContext.presentation?.route === replacement)
        orbit.rootContext.completeDismiss(id: state.id)
        #expect(orbit.rootContext.presentation?.route === replacement)
    }

    @Test("Empty and duplicate declarations reject navigation without changing root")
    func invalidTabDeclarations() {
        let declarations: [[OrbitTab]] = [[], [FirstTab(), FirstTab()]]
        for tabs in declarations {
            let orbit = makeOrbit(tabs: tabs)
            let root = TestRoute()
            orbit.setRoot(root)
            #expect(!orbit.setRoot(TabsRoute()))
            #expect(orbit.rootRoute === root)
            #expect(orbit.rootContext.tabManager == nil)
            #expect(!orbit.present(TabsRoute()))
            #expect(orbit.rootContext.presentation == nil)
        }
    }

    @Test("Rejected commands leave state unchanged and emit diagnostics")
    func validation() {
        let orbit = makeOrbit()
        #expect(!orbit.setRoot(UnregisteredRoute()))
        #expect(orbit.rootRoute == nil)
        #expect(!orbit.selectTab(FirstTab()))
        #expect(!orbit.register(TestRoute.self) { _ in EmptyView() })
        #expect(!orbit.present(UnregisteredRoute()))
        #expect(orbit.rootContext.presentation == nil)
        orbit.setRoot(ContentRoute())
        #expect(!orbit.rootContext.push(TestRoute()))
    }

    #if os(iOS)
    @Test("Full screens and sheets nest without sharing child state")
    func mixedPresentationStyles() throws {
        let orbit = makeOrbit()
        orbit.present(TestRoute(), style: .fullScreen)
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
nonisolated private final class TabsRoute: OrbitRoute {}
nonisolated private final class ModalTabsRoute: OrbitRoute {}
nonisolated private final class UnregisteredRoute: OrbitRoute {}
nonisolated private final class FirstTab: OrbitTab {
    override class var tabName: String { "same-tab-name" }
}
nonisolated private final class SecondTab: OrbitTab {
    override class var tabName: String { "same-tab-name" }
}
