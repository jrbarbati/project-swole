import Foundation
import SwiftData

@Model
public final class SetLog {
    public var exerciseLog: ExerciseLog?
    public var setNumber: Int
    public var repsCompleted: Int?

    public init(exerciseLog: ExerciseLog?, setNumber: Int, repsCompleted: Int?) {
        self.exerciseLog = exerciseLog
        self.setNumber = setNumber
        self.repsCompleted = repsCompleted
    }
}
