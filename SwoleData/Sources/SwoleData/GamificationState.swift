import SwiftData

@Model
public final class GamificationState {
    public var totalXP: Int

    public init(totalXP: Int = 0) {
        self.totalXP = totalXP
    }
}
