import SwiftUI
import SwoleData

/// Shown after `WorkoutSummaryView`'s Save button commits the workout —
/// animates the XP just earned and its bonus breakdown before returning to Today.
struct XPRevealView: View {
    let award: XPAward
    let onDone: () -> Void

    @State private var displayedTotal = 0
    @State private var visibleChipCount = 0
    @State private var barFraction: CGFloat = 0
    @State private var totalScale: CGFloat = 0.7
    @State private var visibleBadgeCount = 0

    private var beforeProgress: (current: Int, needed: Int, level: Int) {
        XPCalculator.progress(forXP: award.xpBefore)
    }
    private var afterProgress: (current: Int, needed: Int, level: Int) {
        XPCalculator.progress(forXP: award.xpAfter)
    }
    private var leveledUp: Bool { afterProgress.level > beforeProgress.level }

    private var startFraction: CGFloat {
        guard !leveledUp, afterProgress.needed > 0 else { return 0 }
        return CGFloat(beforeProgress.current) / CGFloat(afterProgress.needed)
    }
    private var endFraction: CGFloat {
        afterProgress.needed > 0 ? CGFloat(afterProgress.current) / CGFloat(afterProgress.needed) : 0
    }

    private var chips: [BonusChip] {
        var result = [BonusChip(label: "Workout complete", value: award.base)]
        if award.prCount > 0 {
            result.append(BonusChip(
                label: award.prCount == 1 ? "New PR" : "\(award.prCount) new PRs",
                value: award.prBonus
            ))
        }
        if award.perfectBonus > 0 {
            result.append(BonusChip(label: "Perfect workout", value: award.perfectBonus))
        }
        if award.weeklyBonus > 0 {
            result.append(BonusChip(label: "3rd workout this week", value: award.weeklyBonus))
        }
        return result
    }

    private var badges: [Badge] { award.newBadges }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: 10) {
                MetaLabel(text: leveledUp ? "Level Up!" : "XP Earned", color: Theme.accentText)
                    .tracking(1.6)
                Text("+\(displayedTotal)")
                    .font(Theme.Font.display(64))
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText())
                    .scaleEffect(totalScale)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 30)

            chipList
                .padding(.horizontal, Theme.Space.screen)

            if !badges.isEmpty {
                badgeList
                    .padding(.horizontal, Theme.Space.screen)
                    .padding(.top, 18)
            }

            levelBar
                .padding(.top, 26)
                .padding(.horizontal, Theme.Space.screen)

            Spacer(minLength: 0)

            Button(action: onDone) {
                Text("Done")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Theme.accentInk)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Theme.Space.screen)
            .padding(.bottom, 12)
        }
        .background(Theme.canvas)
        .onAppear { animateIn() }
    }

    private var chipList: some View {
        VStack(spacing: 9) {
            ForEach(Array(chips.enumerated()), id: \.offset) { index, chip in
                if index < visibleChipCount {
                    BonusChipRow(chip: chip)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }

    private var badgeList: some View {
        VStack(alignment: .leading, spacing: 9) {
            MetaLabel(text: "New Badges", color: Theme.textDim)
                .tracking(1.2)
            ForEach(Array(badges.enumerated()), id: \.offset) { index, badge in
                if index < visibleBadgeCount {
                    BadgeChipRow(badge: badge)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }

    private var levelBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                MetaLabel(text: "Level \(afterProgress.level)", color: Theme.textDim)
                    .tracking(1.2)
                Spacer()
                MetaLabel(text: "\(afterProgress.current) / \(afterProgress.needed) XP", color: Theme.textDim)
                    .tracking(1.2)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                        .fill(Theme.surfaceSunken)
                    RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                        .fill(Theme.accent)
                        .frame(width: geo.size.width * barFraction)
                }
            }
            .frame(height: 8)
        }
    }

    private func animateIn() {
        barFraction = startFraction

        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
            totalScale = 1
        }
        withAnimation(.easeOut(duration: 0.9)) {
            displayedTotal = award.total
        }

        for index in chips.indices {
            let delay = 0.35 + Double(index) * 0.18
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                    visibleChipCount = index + 1
                }
            }
        }

        let badgesStartDelay = 0.35 + Double(chips.count) * 0.18 + 0.15
        for index in badges.indices {
            let delay = badgesStartDelay + Double(index) * 0.18
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                    visibleBadgeCount = index + 1
                }
            }
        }

        let barDelay = badgesStartDelay + Double(badges.count) * 0.18 + (badges.isEmpty ? 0 : 0.15)
        DispatchQueue.main.asyncAfter(deadline: .now() + barDelay) {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.8)) {
                barFraction = endFraction
            }
        }
    }
}

private struct BonusChip {
    let label: String
    let value: Int
}

private struct BonusChipRow: View {
    let chip: BonusChip

    var body: some View {
        HStack {
            Text(chip.label)
                .font(Theme.Font.body(15))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Text("+\(chip.value) XP")
                .font(Theme.Font.numeric(15))
                .foregroundStyle(Theme.accentText)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, Theme.Space.cardPadding)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.border, lineWidth: 1)
        )
    }
}

private struct BadgeChipRow: View {
    let badge: Badge

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: badge.iconName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.accentInk)
                .frame(width: 32, height: 32)
                .background(Theme.accent, in: Circle())
            Text(badge.title)
                .font(Theme.Font.body(15))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
        }
        .padding(.vertical, 14)
        .padding(.horizontal, Theme.Space.cardPadding)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.border, lineWidth: 1)
        )
    }
}
