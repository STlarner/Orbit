import Orbit
import SwiftUI

nonisolated final class TabsRoute: OrbitRoute {}
nonisolated final class ModalTabsRoute: OrbitRoute {}
nonisolated final class DetailRoute: OrbitRoute {}
nonisolated final class ProfileRoute: OrbitRoute {}
nonisolated final class HomeTab: OrbitTab {}
nonisolated final class TasksTab: OrbitTab {}

@main
struct OrbitDemo: App {
    var body: some Scene {
        WindowGroup { OrbitDemoWindow() }
    }
}

// State belongs to each window, not to the App shared by every WindowGroup scene.
@MainActor
private struct OrbitDemoWindow: View {
    @State private var orbit: Orbit

    init() {
        let orbit = Orbit()
        orbit.register(TabsRoute.self) { _ in
            OrbitTabView {
                OrbitTabItem(HomeTab()) { HomeView() } label: {
                    Label("Home", systemImage: "house")
                }
                OrbitTabItem(TasksTab()) { Text("Tasks") } label: {
                    Label("Tasks", systemImage: "checklist")
                }
            }
            .padding(8)
        }
        orbit.register(ModalTabsRoute.self) { _ in
            OrbitTabView {
                OrbitTabItem(HomeTab()) { ProfileView() } label: { Text("Profile") }
                OrbitTabItem(TasksTab()) { Text("Modal tasks") } label: { Text("Tasks") }
            }
            .wrapped { tabs in AnyView(Group { tabs }.padding(8)) }
        }
        orbit.register(DetailRoute.self) { _ in Text("Detail") }
        orbit.register(ProfileRoute.self) { _ in ProfileView() }
        orbit.setRoot(TabsRoute())
        _orbit = State(initialValue: orbit)
    }

    var body: some View {
        OrbitRootHost(orbit)
    }
}

struct HomeView: View {
    @Environment(\.orbit) private var orbit

    var body: some View {
        VStack {
            Button("Push") { orbit.push(DetailRoute()) }
            Button("Tasks") { orbit.selectTab(TasksTab()) }
            Button("Profile") { orbit.present(ProfileRoute()) }
            Button("Modal tabs") { orbit.present(ModalTabsRoute()) }
        }
        .navigationTitle("Home")
    }
}

struct ProfileView: View {
    @Environment(\.orbit) private var orbit

    var body: some View {
        VStack {
            Button("Push in modal") { orbit.push(DetailRoute()) }
            Button("Nested sheet") { orbit.present(ProfileRoute()) }
            Button("Done") { orbit.dismiss() }
        }
    }
}
