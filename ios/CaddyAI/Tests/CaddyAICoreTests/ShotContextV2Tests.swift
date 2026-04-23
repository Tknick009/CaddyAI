import XCTest
@testable import CaddyAICore

/// Regression + DTO-sync tests for `ShotContext`'s v2 environment and
/// hazard fields. AGENTS.md says the Pydantic and Swift DTOs must stay
/// in sync on the wire (snake_case JSON). This file locks in:
///
///   * the v2 fields are exposed through the public initializer
///   * they round-trip through the shared JSON coders using snake_case keys
///   * omitting them produces the documented default (`null`)
final class ShotContextV2Tests: XCTestCase {

    func testInitExposesAllV2Fields() {
        let ctx = ShotContext(
            targetDistanceYards: 165,
            elevationChangeFt: 12,
            windSpeedMph: 6,
            windDirectionDeg: 30,
            lie: .rough,
            latitude: 37.7749,
            longitude: -122.4194,
            altitudeFt: 50,
            temperatureC: 18,
            pressureHpa: 1013,
            humidityPct: 55,
            hazardLeftYards: 20,
            hazardRightYards: 12
        )
        XCTAssertEqual(ctx.latitude, 37.7749)
        XCTAssertEqual(ctx.longitude, -122.4194)
        XCTAssertEqual(ctx.altitudeFt, 50)
        XCTAssertEqual(ctx.temperatureC, 18)
        XCTAssertEqual(ctx.pressureHpa, 1013)
        XCTAssertEqual(ctx.humidityPct, 55)
        XCTAssertEqual(ctx.hazardLeftYards, 20)
        XCTAssertEqual(ctx.hazardRightYards, 12)
    }

    func testV2FieldsSerializeAsSnakeCase() throws {
        let ctx = ShotContext(
            targetDistanceYards: 150,
            latitude: 12.5,
            longitude: -80.25,
            altitudeFt: 500,
            temperatureC: 22,
            pressureHpa: 1012,
            humidityPct: 60,
            hazardLeftYards: 18,
            hazardRightYards: 15
        )
        let data = try CaddyAIJSON.encoder.encode(ctx)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        // snake_case keys are required by the Pydantic-side DTO.
        XCTAssertEqual(json["latitude"] as? Double, 12.5)
        XCTAssertEqual(json["longitude"] as? Double, -80.25)
        XCTAssertEqual(json["altitude_ft"] as? Double, 500)
        XCTAssertEqual(json["temperature_c"] as? Double, 22)
        XCTAssertEqual(json["pressure_hpa"] as? Double, 1012)
        XCTAssertEqual(json["humidity_pct"] as? Double, 60)
        XCTAssertEqual(json["hazard_left_yards"] as? Double, 18)
        XCTAssertEqual(json["hazard_right_yards"] as? Double, 15)
        // no camelCase leaks
        XCTAssertNil(json["altitudeFt"])
        XCTAssertNil(json["hazardLeftYards"])
    }

    func testRoundTripPreservesV2Fields() throws {
        let original = ShotContext(
            targetDistanceYards: 175,
            elevationChangeFt: -8,
            windSpeedMph: 10,
            windDirectionDeg: 180,
            lie: .fairway,
            latitude: 39.7392,
            longitude: -104.9903,
            altitudeFt: 5280,
            temperatureC: 22,
            pressureHpa: 840,
            humidityPct: 30,
            hazardLeftYards: 25,
            hazardRightYards: 22
        )
        let data = try CaddyAIJSON.encoder.encode(original)
        let decoded = try CaddyAIJSON.decoder.decode(ShotContext.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testV2FieldsDefaultToNilWhenOmitted() throws {
        let ctx = ShotContext(targetDistanceYards: 150)
        XCTAssertNil(ctx.latitude)
        XCTAssertNil(ctx.longitude)
        XCTAssertNil(ctx.altitudeFt)
        XCTAssertNil(ctx.temperatureC)
        XCTAssertNil(ctx.pressureHpa)
        XCTAssertNil(ctx.humidityPct)
        XCTAssertNil(ctx.hazardLeftYards)
        XCTAssertNil(ctx.hazardRightYards)
    }

    /// Backward compat: servers or older clients sending only the v1
    /// payload must still decode into a valid ShotContext.
    func testDecodesLegacyV1PayloadWithoutV2Fields() throws {
        let legacyJSON = """
        {
          "target_distance_yards": 150,
          "elevation_change_ft": 0,
          "wind_speed_mph": 0,
          "wind_direction_deg": 0,
          "lie": "fairway",
          "avoid_left": false,
          "avoid_right": false
        }
        """
        let data = Data(legacyJSON.utf8)
        let ctx = try CaddyAIJSON.decoder.decode(ShotContext.self, from: data)
        XCTAssertEqual(ctx.targetDistanceYards, 150)
        XCTAssertNil(ctx.altitudeFt)
        XCTAssertNil(ctx.hazardLeftYards)
    }
}
