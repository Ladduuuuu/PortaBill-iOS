import SwiftUI

@main
struct PortaBillApp: App {
    @State private var env = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(env)
                .preferredColorScheme(.light)
                .tint(Theme.primary)
                .task { await env.bootstrap() }
        }
    }
}

struct RootView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        Group {
            if env.isRestoring {
                ZStack {
                    Theme.background.ignoresSafeArea()
                    ProgressView()
                }
            } else if env.session == nil {
                LoginView()
            } else {
                MainTabView()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: env.session == nil)
    }
}

struct MainTabView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        @Bindable var env = env

        TabView(selection: $env.selectedTab) {
            NavigationStack(path: $env.areasPath) {
                AreasView()
                    .navigationDestination(for: Route.self) { route in
                        switch route {
                        case .accounts(let area):
                            AccountsView(area: area)
                        case .reading(let gid, let category):
                            ReadingEntryView(accountGid: gid, initialCategory: category)
                        }
                    }
            }
            .tabItem { Label("Areas", systemImage: "map") }
            .tag(AppTab.areas)

            QueueView()
                .tabItem { Label("Queue", systemImage: "tray.and.arrow.up") }
                .badge(env.pendingCount)
                .tag(AppTab.queue)

            SignOutView()
                .tabItem { Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right") }
                .tag(AppTab.signOut)
        }
    }
}

struct SignOutView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var showBlocked = false
    @State private var showConfirm = false
    @State private var errorText = ""

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 20) {
                Spacer()
                ZStack {
                    Circle().fill(Theme.primaryTint).frame(width: 96, height: 96)
                    Image(systemName: "person.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(Theme.primary)
                }
                VStack(spacing: 4) {
                    Text(env.session?.staffName ?? "").font(.title2.weight(.bold)).foregroundStyle(Theme.ink)
                    Text("Signed in").font(.subheadline).foregroundStyle(Theme.muted)
                }

                Button("Sign Out") { requestSignOut() }
                    .buttonStyle(PrimaryButtonStyle(tint: Theme.danger))
                    .padding(.horizontal, 32)
                    .padding(.top, 8)

                if !errorText.isEmpty {
                    Text(errorText).font(.footnote).foregroundStyle(Theme.danger)
                }
                Spacer()
                Text(AppConfig.appVersion).font(.footnote).foregroundStyle(Theme.muted)
            }
            .padding()
        }
        .task { await env.refreshPendingCount() }
        .confirmationDialog("Sign out?", isPresented: $showConfirm, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) { Task { await env.signOut() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Local data for your assigned areas will be removed from this device.")
        }
        .alert("Cannot Sign Out", isPresented: $showBlocked) {
            Button("View Queue") { env.selectedTab = .queue }
            Button("OK", role: .cancel) {}
        } message: {
            Text("You have \(env.pendingCount) unsynchronized meter readings. Please ensure all readings are synchronized before signing out.\n\nWould you like to go to the Queue page to monitor sync status?")
        }
    }

    private func requestSignOut() {
        Task {
            await env.refreshPendingCount()
            if env.pendingCount > 0 {
                showBlocked = true
            } else {
                showConfirm = true
            }
        }
    }
}
