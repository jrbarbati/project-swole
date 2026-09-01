public enum RestOutcome: Equatable, Sendable {
    case success
    case fail
}

public enum RepCycle {
    public static func next(current: Int?, target: Int) -> Int? {
        guard let current else {
            return target
        }
        
        if current == 0 {
            return nil
        }
        
        return current - 1
    }
}
