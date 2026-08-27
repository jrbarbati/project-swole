import Foundation
import SwiftData

@Model
public final class Exercise {
    public var name: String
    public var defaultSetCount: Int
    public var defaultRepsPerSet: Int

    public init(name: String, defaultSetCount: Int, defaultRepsPerSet: Int) {
        self.name = name
        self.defaultSetCount = defaultSetCount
        self.defaultRepsPerSet = defaultRepsPerSet
    }
}
