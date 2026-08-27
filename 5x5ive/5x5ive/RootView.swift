import SwiftUI
import SwiftData
import SwoleData

struct RootView: View {
    @Query(filter: #Predicate<WorkoutSession> { $0.finishedAt == nil },
           sort: \WorkoutSession.startedAt, order: .reverse)
    private var activeSessions: [WorkoutSession]

    @State private var selectedTab: Tab = .today

    enum Tab: Hashable { case today, history, settings }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack { TodayView() }
                .tag(Tab.today)
                .tabItem { Label("Today", systemImage: "square.grid.2x2") }

            NavigationStack { HistoryView() }
                .tag(Tab.history)
                .tabItem { Label("History", systemImage: "list.bullet") }

            NavigationStack { SettingsView() }
                .tag(Tab.settings)
                .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
        }
        .tint(Theme.accent)
        .background(Theme.canvas)
        // The design shows a flat, monospaced tab bar rather than the stock
        // iOS one. If you want to match the mock exactly, drop the .tabItem
        // labels above, hide the system bar, and render CustomTabBar (below)
        // inside a VStack. Keeping the system bar is a legitimate call —
        // it gets you accessibility and haptics for free.
        .fullScreenCover(item: activeSessions.first) { session in
            ActiveWorkoutView(session: session)
        }
    }
}

// MARK: - Optional custom tab bar (matches mock 01/08/10)

struct CustomTabBar: View {
    @Binding var selection: RootView.Tab

    private let items: [(tab: RootView.Tab, title: String)] = [
        (.today, "Today"), (.history, "History"), (.settings, "Settings"),
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

// MARK: - fullScreenCover(item:) shim
// SwiftData models are Identifiable; this keeps the call site readable.

private extension View {
    func fullScreenCover<Item: Identifiable, Content: View>(
        item: Item?,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        modifier(FullScreenItemModifier(item: item, sheetContent: content))
    }
}

private struct FullScreenItemModifier<Item: Identifiable, SheetContent: View>: ViewModifier {
    let item: Item?
    let sheetContent: (Item) -> SheetContent

    func body(content: Content) -> some View {
        content.fullScreenCover(isPresented: .constant(item != nil)) {
            if let item { sheetContent(item) }
        }
    }
}
