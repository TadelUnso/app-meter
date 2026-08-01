import Foundation
import Testing
@testable import AppMeterCore

@Suite("Install history")
struct InstallHistoryTests {
    /// The exact shape every file on disk has today — written before `version`
    /// existed. It must decode rather than be rejected, or every user's cache
    /// is thrown away the moment this field ships.
    @Test func aFileWrittenBeforeVersionExistedDecodesAsVersionOne() throws {
        let json = """
        {"periods":{"YEARLY:2025":{"111":40}},"titles":{"111":"Finder"}}
        """.data(using: .utf8)!

        let history = try JSONDecoder().decode(InstallHistory.self, from: json)

        #expect(history.version == 1)
        #expect(history.units(for: .yearly(2025)) == ["111": 40])
    }

    /// A file a future release wrote carries its own version through.
    @Test func aVersionedFileDecodesItsOwnVersion() throws {
        let json = """
        {"version":2,"periods":{},"titles":{}}
        """.data(using: .utf8)!

        let history = try JSONDecoder().decode(InstallHistory.self, from: json)

        #expect(history.version == 2)
    }

    @Test func defaultsToVersionOneWhenBuiltInMemory() {
        #expect(InstallHistory().version == 1)
    }

    /// Round-trips through the real encoder, not just hand-written JSON.
    @Test func encodingThenDecodingPreservesVersion() throws {
        let original = InstallHistory(periods: ["2025": ["111": 40]], titles: ["111": "Finder"], version: 3)

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(InstallHistory.self, from: data)

        #expect(decoded == original)
    }
}
