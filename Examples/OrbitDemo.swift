import Orbit
import SwiftUI

nonisolated final class TabsRoute: OrbitRoute {}
nonisolated final class DetailRoute: OrbitRoute {}
nonisolated final class ProfileRoute: OrbitRoute {}
nonisolated final class HomeTab: OrbitTab {}
nonisolated final class TasksTab: OrbitTab {}

@main
struct OrbitDemo: App {
    @State private var orbit: Orbit

    init() {
        let orbit = Orbit(tabs: [HomeTab(), TasksTab()])
        orbit.register(TabsRoute.self, navigation: .content) { _ in TabsView() }
        orbit.register(DetailRoute.self) { _ in Text("Detail") }
        orbit.register(ProfileRoute.self) { _ in ProfileView() }
        _orbit = State(initialValue: orbit)
    }

    var body: some Scene {
        WindowGroup {
            OrbitRootHost(orbit) {
                ProgressView().task { orbit.setRoot(TabsRoute()) }
            }
        }
    }
}

struct TabsView: View {
    @Environment(\.orbitTabs) private var tabs

    var body: some View {
        if let tabs {
            TabView(selection: Binding(
                get: { tabs.selectedTab },
                set: { if let tab = $0 { tabs.select(tab) } }
            )) {
                if let context = tabs.context(for: HomeTab()) {
                    OrbitNavigationHost(context) { HomeView() }
                        .tabItem { Label("Home", systemImage: "house") }
                        .tag(HomeTab() as OrbitTab?)
                }
                if let context = tabs.context(for: TasksTab()) {
                    OrbitNavigationHost(context) { Text("Tasks") }
                        .tabItem { Label("Tasks", systemImage: "checklist") }
                        .tag(TasksTab() as OrbitTab?)
                }
            }
        }
    }
}

struct HomeView: View {
    @Environment(\.orbit) private var orbit

    var body: some View {
        VStack {
            Button("Push") { orbit.push(DetailRoute()) }
            Button("Profile") { orbit.present(ProfileRoute(), style: .sheet) }
        }
    }
}

struct ProfileView: View {
    @Environment(\.orbit) private var orbit

    var body: some View {
        VStack {
            Button("Push in modal") { orbit.push(DetailRoute()) }
            Button("Nested sheet") { orbit.present(ProfileRoute(), style: .sheet) }
            Button("Done") { orbit.dismiss() }
        }
    }
}
