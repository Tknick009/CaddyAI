import XCTest
@testable import CaddyAICore

final class CaddyEngineTests: XCTestCase {
    func bag() -> Bag {
        Bag(
            clubs: Bag.standard14.clubs,
            personalDistances: [
                PersonalDistance(clubId: "7i", typicalYards: 150, stddevYards: 4, sampleSize: 40),
                PersonalDistance(clubId: "8i", typicalYards: 140, stddevYards: 4, sampleSize: 40),
                PersonalDistance(clubId: "6i", typicalYards: 160, stddevYards: 4, sampleSize: 40),
                PersonalDistance(clubId: "pw", typicalYards: 115, stddevYards: 3, sampleSize: 40),
            ]
        )
    }

    func testStock150PicksSevenIron() throws {
        let rec = try XCTUnwrap(CaddyEngine.recommend(ShotContext(targetDistanceYards: 150), bag: bag()))
        XCTAssertEqual(rec.primaryClubId, "7i")
    }

    func testHeadwindClubsUp() throws {
        let ctx = ShotContext(targetDistanceYards: 150, windSpeedMph: 8, windDirectionDeg: 0)
        let rec = try XCTUnwrap(CaddyEngine.recommend(ctx, bag: bag()))
        XCTAssertEqual(rec.primaryClubId, "6i")
        XCTAssertGreaterThan(rec.windAdjustmentYards, 0)
    }

    func testUphillClubsUp() throws {
        let ctx = ShotContext(targetDistanceYards: 150, elevationChangeFt: 30)
        let rec = try XCTUnwrap(CaddyEngine.recommend(ctx, bag: bag()))
        XCTAssertEqual(rec.primaryClubId, "6i")
    }

    func testBunkerLieAddsDistance() throws {
        let ctx = ShotContext(targetDistanceYards: 140, lie: .bunker)
        let rec = try XCTUnwrap(CaddyEngine.recommend(ctx, bag: bag()))
        XCTAssertGreaterThan(rec.lieAdjustmentYards, 0)
    }

    func testEmptyBagReturnsNil() {
        XCTAssertNil(CaddyEngine.recommend(ShotContext(targetDistanceYards: 150), bag: Bag()))
    }
}
