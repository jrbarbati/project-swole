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
            }
            .padding(.bottom, 24)
        }
        .background(Theme.canvas)
        .toolbar(.hidden, for: .navigationBar)
        .task { await loadAll() }
        .onChange(of: range) { _, _ in Task { await loadAll() } }
        .onChange(of: selectedExercise) { _, _ in Task { await loadTrend() } }
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
        case .fourWeeks: return "4 WEEKS"
        case .twelveWeeks: return "12 WEEKS"
        case .all: return "ALL TIME"
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

            exerciseFilterStrip
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

    // Horizontal scroll keeps five lifts on one line at any Dynamic Type size.
    private var exerciseFilterStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(exercises) { exercise in
                    let isSelected = exercise == selectedExercise
                    Button {
                        selectedExercise = exercise
                    } label: {
                        Text(exercise.name.uppercased())
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
