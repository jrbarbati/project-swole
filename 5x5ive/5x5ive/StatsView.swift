import SwiftUI
import SwiftData
import Charts
import SwoleData

struct StatsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @Query private var settingsList: [UserSettings]

    @State private var range: StatsRange = .twelveWeeks
    @State private var totals: StatsTotals?
    @State private var streak: StreakInfo?
    @State private var volumePoints: [VolumePoint] = []
    @State private var records: [PersonalRecord] = []
    @State private var selectedExercise: Exercise?
    @State private var trendLogs: [ExerciseLog] = []
    @State private var badges: [Badge] = []
    @State private var selectedBadge: Badge?

    private var unit: MeasurementUnit { settingsList.first?.unit ?? .lb }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Stats")
                    .font(Theme.Font.display(34))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, Theme.Space.screen)
                    .padding(.top, 14)

                rangePicker
                    .padding(.top, 16)
                    .padding(.horizontal, Theme.Space.screen)

                streakCard
                volumeCard
                strengthCard
                recordsCard
                badgesCard
            }
            .padding(.bottom, 24)
        }
        .background(Theme.canvas)
        .toolbar(.hidden, for: .navigationBar)
        .task { await loadAll() }
        .onChange(of: range) { _, _ in Task { await loadAll() } }
        .onChange(of: selectedExercise) { _, _ in Task { await loadTrend() } }
        .sheet(item: $selectedBadge) { badge in
            BadgeDetailSheet(badge: badge, unit: unit)
                .presentationDetents([.height(260)])
        }
    }

    // MARK: - Range picker

    private var rangePicker: some View {
        HStack(spacing: 7) {
            ForEach([StatsRange.fourWeeks, .twelveWeeks, .all], id: \.self) { option in
                let isSelected = option == range
                Button {
                    range = option
                } label: {
                    Text(rangeLabel(option))
                        .font(Theme.Font.label(10))
                        .tracking(1)
                        .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textDim)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(
                            isSelected ? Theme.surfaceSunken : .clear,
                            in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func rangeLabel(_ range: StatsRange) -> String {
        switch range {
        case .fourWeeks: "4 WEEKS"
        case .twelveWeeks: "12 WEEKS"
        case .all: "ALL TIME"
        }
    }

    // MARK: - Cards

    private var streakCard: some View {
        card {
            MetaLabel(text: "Consistency").tracking(1.6)
            HStack(spacing: 28) {
                statBlock(value: "\(streak?.currentWeeks ?? 0)", label: "week streak")
                statBlock(value: "\(streak?.longestWeeks ?? 0)", label: "longest")
                statBlock(value: "\(totals?.workoutCount ?? 0)", label: "workouts")
            }
        }
    }

    private var volumeCard: some View {
        card {
            HStack(alignment: .firstTextBaseline) {
                MetaLabel(text: "Volume").tracking(1.6)
                Spacer()
                if let totals {
                    MetaLabel(
                        text: "\(unit.fromLb(totals.totalVolume).formatted(.number.precision(.fractionLength(0)))) \(unit.rawValue)",
                        color: Theme.accentText
                    )
                }
            }

            VolumeBarChart(points: volumePoints)
                .frame(height: 90)

            HStack {
                MetaLabel(text: "avg / workout", color: Theme.textDim)
                Spacer()
                MetaLabel(text: "\(unit.fromLb(averageVolumePerWorkout).formatted(.number.precision(.fractionLength(0)))) \(unit.rawValue)", color: Theme.textDim)
            }
        }
    }

    private var strengthCard: some View {
        card {
            HStack(alignment: .firstTextBaseline) {
                MetaLabel(text: "\(selectedExercise?.name ?? "—") · working weight").tracking(1.6)
                Spacer()
                if let latest = trendLogs.last?.targetWeight {
                    MetaLabel(text: "\(unit.fromLb(latest).formattedWeight) \(unit.rawValue)", color: Theme.accentText)
                }
            }

            if trendLogs.isEmpty {
                MetaLabel(text: "no sessions in range", color: Theme.textFaint)
                    .frame(height: 76)
            } else {
                WeightTrendChart(logs: trendLogs.dropLast(), currentWeight: trendLogs.last?.targetWeight ?? 0, unit: unit)
                    .frame(height: 76)
            }

            ExerciseFilterStrip(exercises: exercises, selectedExercise: $selectedExercise)
        }
    }

    private var recordsCard: some View {
        card {
            MetaLabel(text: "Personal Records").tracking(1.6)
            VStack(spacing: 0) {
                ForEach(records) { record in
                    recordRow(record)
                }
            }
        }
    }

    private var badgesCard: some View {
        card {
            HStack(alignment: .firstTextBaseline) {
                MetaLabel(text: "Badges").tracking(1.6)
                Spacer()
                MetaLabel(text: "\(unlockedBadgeCount) / \(badges.count) earned", color: Theme.accentText)
            }

            ForEach(badgeGroups, id: \.title) { group in
                VStack(alignment: .leading, spacing: 10) {
                    MetaLabel(text: group.title, color: Theme.textDim)
                    LazyVGrid(columns: badgeGridColumns, spacing: 12) {
                        ForEach(group.badges) { badge in
                            BadgeTile(badge: badge)
                                .onTapGesture { selectedBadge = badge }
                        }
                    }
                }
            }
        }
    }

    private var unlockedBadgeCount: Int { badges.filter(\.isUnlocked).count }

    private let badgeGridColumns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)

    private struct BadgeGroup {
        let title: String
        let badges: [Badge]
    }

    private var badgeGroups: [BadgeGroup] {
        var groups: [BadgeGroup] = []

        let streakBadges = badges.filter { $0.category == .streak }
        if !streakBadges.isEmpty { groups.append(BadgeGroup(title: "Streaks", badges: streakBadges)) }

        let countBadges = badges.filter { $0.category == .workoutCount }
        if !countBadges.isEmpty { groups.append(BadgeGroup(title: "Workouts", badges: countBadges)) }

        let totalBadges = badges.filter { $0.category == .totalVolume }
        if !totalBadges.isEmpty { groups.append(BadgeGroup(title: "Total Volume", badges: totalBadges)) }

        for exercise in exercises {
            let exerciseBadges = badges.filter {
                guard case .exerciseVolume(let name) = $0.category else { return false }
                return name == exercise.name
            }
            if !exerciseBadges.isEmpty { groups.append(BadgeGroup(title: exercise.name, badges: exerciseBadges)) }
        }

        return groups
    }

    private func recordRow(_ record: PersonalRecord) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(record.exercise.name)
                .font(Theme.Font.title(15))
                .foregroundStyle(Theme.textPrimary)

            if record.isWithinRange {
                MetaLabel(text: "new", color: Theme.accentText)
            }

            Spacer()

            Text("\(unit.fromLb(record.weight).formattedWeight) \(unit.rawValue) × \(record.reps)")
                .font(Theme.Font.numeric(14))
                .foregroundStyle(Theme.textMuted)
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.hairline).frame(height: 1)
        }
    }

    private func statBlock(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(Theme.Font.numeric(28, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            MetaLabel(text: label)
        }
    }

    @ViewBuilder
    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            content()
        }
        .padding(18)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Theme.border, lineWidth: 1)
        )
        .padding(.top, 22)
        .padding(.horizontal, Theme.Space.screen)
    }

    private var averageVolumePerWorkout: Double {
        guard let totals, totals.workoutCount > 0 else { return 0 }
        return totals.totalVolume / Double(totals.workoutCount)
    }

    // MARK: - Loading

    @MainActor
    private func loadAll() async {
        totals = try? StatsCalculator.totals(range: range, in: modelContext)
        streak = try? StatsCalculator.streaks(in: modelContext)
        volumePoints = (try? StatsCalculator.weeklyVolume(range: range, in: modelContext)) ?? []
        records = (try? StatsCalculator.personalRecords(range: range, in: modelContext)) ?? []
        badges = (try? BadgeCalculator.allBadges(unit: unit, in: modelContext)) ?? []
        if selectedExercise == nil { selectedExercise = exercises.first }
        await loadTrend()
    }

    @MainActor
    private func loadTrend() async {
        guard let exercise = selectedExercise else { return }
        trendLogs = (try? StatsCalculator.trendLogs(for: exercise, range: range, in: modelContext)) ?? []
    }
}

// MARK: - Weekly volume chart

private struct VolumeBarChart: View {
    let points: [VolumePoint]

    var body: some View {
        Chart(points) { point in
            BarMark(
                x: .value("Week", point.weekStart, unit: .weekOfYear),
                y: .value("Volume", point.volume)
            )
            .foregroundStyle(Theme.accent)
            .cornerRadius(3)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
    }
}

// MARK: - Badges

private struct BadgeTile: View {
    let badge: Badge

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(badge.isUnlocked ? Theme.accent : Theme.surfaceSunken)
                    .frame(width: 44, height: 44)
                Image(systemName: badge.isUnlocked ? badge.iconName : "lock.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(badge.isUnlocked ? Theme.accentInk : Theme.textFaint)
            }
            Text(badge.progressTarget.formatted(.number.precision(.fractionLength(0))))
                .font(Theme.Font.numeric(11))
                .foregroundStyle(badge.isUnlocked ? Theme.textPrimary : Theme.textFaint)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct BadgeDetailSheet: View {
    let badge: Badge
    let unit: MeasurementUnit

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: badge.iconName)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(badge.isUnlocked ? Theme.accentText : Theme.textFaint)
                .frame(width: 72, height: 72)
                .background(badge.isUnlocked ? Theme.accent.opacity(0.15) : Theme.surfaceSunken, in: Circle())

            Text(badge.title)
                .font(Theme.Font.title(19))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)

            if badge.isUnlocked, let unlockedAt = badge.unlockedAt {
                MetaLabel(text: "Earned \(unlockedAt.formatted(date: .abbreviated, time: .omitted))", color: Theme.accentText)
            } else {
                VStack(spacing: 6) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                                .fill(Theme.surfaceSunken)
                            RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                                .fill(Theme.accent)
                                .frame(width: geo.size.width * progressFraction)
                        }
                    }
                    .frame(height: 8)
                    MetaLabel(text: "\(formattedProgress(badge.progressCurrent)) / \(formattedProgress(badge.progressTarget)) \(unitLabel)", color: Theme.textDim)
                }
            }
        }
        .padding(24)
    }

    private var progressFraction: CGFloat {
        guard badge.progressTarget > 0 else { return 0 }
        return min(CGFloat(badge.progressCurrent / badge.progressTarget), 1)
    }

    private var unitLabel: String {
        switch badge.category {
        case .exerciseVolume, .totalVolume: unit.rawValue
        case .workoutCount: "workouts"
        case .streak: "weeks"
        }
    }

    private func formattedProgress(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)))
    }
}
