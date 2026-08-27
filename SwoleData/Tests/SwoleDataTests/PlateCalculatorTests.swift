import Testing
@testable import SwoleData

@Test func platesAtOrBelowBarWeightNeedsNoPlates() {
    let math = PlateCalculator.plates(for: 45, barWeight: 45, available: PlateCalculator.lbPlates)
    #expect(math.perSide.isEmpty)
    #expect(math.remainder == 0)
    #expect(math.isExact)
    #expect(math.shortDescription == "BAR ONLY")
}

@Test func platesBelowBarWeightAlsoNeedsNoPlates() {
    let math = PlateCalculator.plates(for: 20, barWeight: 45, available: PlateCalculator.lbPlates)
    #expect(math.perSide.isEmpty)
}

@Test func platesPicksTheSinglePlateThatExactlyFillsOneSide() {
    let math = PlateCalculator.plates(for: 135, barWeight: 45, available: PlateCalculator.lbPlates)
    #expect(math.perSide == [45])
    #expect(math.isExact)
    #expect(math.shortDescription == "45")
}

@Test func platesGreedilyPicksMultipleOfTheSamePlate() {
    let math = PlateCalculator.plates(for: 225, barWeight: 45, available: PlateCalculator.lbPlates)
    #expect(math.perSide == [45, 45])
    #expect(math.isExact)
}

@Test func platesMixesDenominationsHeaviestFirst() {
    let math = PlateCalculator.plates(for: 140, barWeight: 45, available: PlateCalculator.lbPlates)
    #expect(math.perSide == [45, 2.5])
    #expect(math.isExact)
    #expect(math.shortDescription == "45 · 2.5")
}

@Test func platesReportsARemainderWhenTargetIsNotLoadableWithAvailablePlates() {
    let math = PlateCalculator.plates(for: 141, barWeight: 45, available: PlateCalculator.lbPlates)
    #expect(math.perSide == [45, 2.5])
    #expect(!math.isExact)
    #expect(math.remainder == 1)
}

@Test func barWeightIsFortyFiveForPoundsAndTwentyForKilograms() {
    #expect(PlateCalculator.barWeight(for: .lb) == 45)
    #expect(PlateCalculator.barWeight(for: .kg) == 20)
}

@Test func plateSetSelectsThePlateFamilyForTheUnit() {
    #expect(PlateCalculator.plateSet(for: .lb) == PlateCalculator.lbPlates)
    #expect(PlateCalculator.plateSet(for: .kg) == PlateCalculator.kgPlates)
}

@Test func kilogramPlatesUseTheirOwnDenominations() {
    let math = PlateCalculator.plates(for: 100, barWeight: 20, available: PlateCalculator.kgPlates)
    #expect(math.perSide == [25, 15])
    #expect(math.isExact)
}
