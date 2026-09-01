import SwiftUI
import SwiftData
import SwoleData

struct RootView: View {
    @Query(filter: #Predicate<WorkoutSession> { $0.finishedAt == nil },
           sort: \WorkoutSession.startedAt, order: .reverse)
    private var activeSessions: [WorkoutSession]

    @Environment(\.scenePhase) private var scenePhase

    @State private var selectedTab: Tab = .today
    /// Snapshot of the presented session, deliberately NOT recomputed from
    /// `activeSessions` on every change: `finishWorkout` sets `finishedAt`
    /// (which drops the session from that query) while the workout's XP
    /// reveal screen still needs to stay on screen, so presentation is
    /// cleared only by an explicit dismiss, not reactively by the query.
    @State private var presentedSession: WorkoutSession?

    enum Tab: Hashable { case today, history, stats, settings }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                tabContent(.today) { NavigationStack { TodayView() } }
                tabContent(.history) { NavigationStack { HistoryView() } }
                tabContent(.stats) { NavigationStack { StatsView() } }
                tabContent(.settings) { NavigationStack { SettingsView() } }
            }

            if let session = activeSessions.first, presentedSession == nil {
                ActiveWorkoutBar(session: session) { presentedSession = session }
            }

            CustomTabBar(selection: $selectedTab)
        }
        .tint(Theme.accent)
        .background(Theme.canvas)
        .fullScreenCover(item: $presentedSession) { session in
            ActiveWorkoutView(session: session)
        }
        .onAppear { presentedSession = activeSessions.first }
        .onChange(of: activeSessions.first?.persistentModelID) { _, newID in
            guard newID != nil, presentedSession == nil else { return }
            presentedSession = activeSessions.first
        }
        .onChange(of: scenePhase) { _, newPhase in
            handleScenePhaseChange(newPhase)
        }
    }

    /// Schedules a local notification for the active session's rest window
    /// on backgrounding (only moment the countdown isn't visible somewhere);
    /// cancels it once the user is back in the app.
    private func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .background:
            guard let session = activeSessions.first, let end = session.restEndDate else {
                return
            }

            let body = RestCompleteMessages.random()

            Task { await NotificationManager.shared.scheduleRestComplete(restEndDate: end, body: body) }
        case .active:
            NotificationManager.shared.cancelRestComplete()
        default:
            break
        }
    }

    /// Keeps every tab's view mounted so switching back preserves its state,
    /// matching TabView's behavior without pulling in its native tab bar chrome.
    @ViewBuilder
    private func tabContent<Content: View>(_ tab: Tab, @ViewBuilder content: () -> Content) -> some View {
        content()
            .opacity(selectedTab == tab ? 1 : 0)
            .allowsHitTesting(selectedTab == tab)
            .accessibilityHidden(selectedTab != tab)
    }
}

struct CustomTabBar: View {
    @Binding var selection: RootView.Tab

    private let items: [(tab: RootView.Tab, title: String)] = [
        (.today, "Today"), (.history, "History"), (.stats, "Stats"), (.settings, "Settings"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.tab) { item in
                let isSelected = selection == item.tab
                Button {
                    selection = item.tab
                } label: {
                    VStack(spacing: 7) {
                        Circle()
                            .fill(isSelected ? Theme.accent : .clear)
                            .frame(width: 5, height: 5)
                        Text(item.title.uppercased())
                            .font(Theme.Font.label())
                            .tracking(1.2)
                            .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textDim)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: Theme.minTouchTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 20)
        .padding(.horizontal, Theme.Space.screen)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }
}
