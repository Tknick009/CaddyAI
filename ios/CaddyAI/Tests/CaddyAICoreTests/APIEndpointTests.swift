import XCTest
@testable import CaddyAICore

final class APIEndpointTests: XCTestCase {

    private let base = URL(string: "http://localhost:8000")!

    func testPathOnly() throws {
        let u = try APIEndpoint.url(base: base, path: "/coach/swing")
        XCTAssertEqual(u.absoluteString, "http://localhost:8000/coach/swing")
    }

    /// Regression: `URL.appendingPathComponent` used to percent-encode
    /// `?` in query strings to `%3F`, producing 404s on the backend.
    /// The path here contains no `?` because we now pass query items
    /// separately — the point is that the final URL has the right
    /// shape regardless of how the caller split it.
    func testQueryItemsLandInQueryNotPath() throws {
        let u = try APIEndpoint.url(
            base: base,
            path: "/coach/swing/history",
            query: [URLQueryItem(name: "limit", value: "20")]
        )
        XCTAssertEqual(u.absoluteString, "http://localhost:8000/coach/swing/history?limit=20")
        XCTAssertFalse(u.absoluteString.contains("%3F"))
    }

    func testAppendsMissingLeadingSlash() throws {
        let u = try APIEndpoint.url(base: base, path: "bag")
        XCTAssertEqual(u.absoluteString, "http://localhost:8000/bag")
    }

    func testDoesNotDoubleSlashWhenBaseEndsWithSlash() throws {
        let base = URL(string: "http://localhost:8000/")!
        let u = try APIEndpoint.url(base: base, path: "/bag")
        XCTAssertEqual(u.absoluteString, "http://localhost:8000/bag")
    }

    func testJoinsSubpathBase() throws {
        let base = URL(string: "https://example.com/api")!
        let u = try APIEndpoint.url(
            base: base,
            path: "/coach/swing/history",
            query: [URLQueryItem(name: "limit", value: "5")]
        )
        XCTAssertEqual(u.absoluteString, "https://example.com/api/coach/swing/history?limit=5")
    }

    func testEmptyQueryOmitsQuestionMark() throws {
        let u = try APIEndpoint.url(base: base, path: "/coach/swing", query: [])
        XCTAssertEqual(u.absoluteString, "http://localhost:8000/coach/swing")
    }

    func testMultipleQueryItemsAreAllPresent() throws {
        let u = try APIEndpoint.url(
            base: base,
            path: "/coach/swing/history",
            query: [
                URLQueryItem(name: "limit", value: "10"),
                URLQueryItem(name: "offset", value: "5"),
            ]
        )
        XCTAssertTrue(u.absoluteString.contains("limit=10"))
        XCTAssertTrue(u.absoluteString.contains("offset=5"))
        XCTAssertTrue(u.absoluteString.contains("?"))
        XCTAssertFalse(u.absoluteString.contains("%3F"))
    }

    func testEncodesUnsafeQueryValues() throws {
        // `URLQueryItem` percent-encodes the *value* itself; the `?`
        // separator between path and query must remain literal.
        let u = try APIEndpoint.url(
            base: base,
            path: "/search",
            query: [URLQueryItem(name: "q", value: "iron & wedge")]
        )
        XCTAssertTrue(u.absoluteString.hasPrefix("http://localhost:8000/search?"))
        XCTAssertTrue(u.absoluteString.contains("iron") && u.absoluteString.contains("wedge"))
    }
}
