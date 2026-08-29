import SwiftUI
import SwiftData
import SwoleData

struct RootView: View {
    @Query(filter: #Predicate<WorkoutSession> { $0.finishedAt == nil },
           sort: \WorkoutSession.startedAt, order: .reverse)
    private var activeSessions: [WorkoutSession]

    @State private var selectedTab: Tab = .today

    enum Tab: Hashable { case today, history, stats, settings }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                tabContent(.today) { NavigationStack { TodayView() } }
                tabContent(.history) { NavigationStack { HistoryView() } }
                tabContent(.stats) { NavigationStack { StatsView() } }
                tabContent(.settings) { NavigationStack { SettingsView() } }
            }

            CustomTabBar(selection: $selectedTab)
        }
        .tint(Theme.accent)
        .background(Theme.canvas)
        .fullScreenCover(isPresented: .constant(activeSessions.first != nil)) {
            if let session = activeSessions.first {
                ActiveWorkoutView(session: session)
            }
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
