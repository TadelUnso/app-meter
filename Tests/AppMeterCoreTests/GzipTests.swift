import Foundation
import Testing
@testable import AppMeterCore

@Suite("Gzip")
struct GzipTests {
    /// Both fixtures are real gzip output, not hand-assembled: the second was
    /// compressed from a file, so it carries an FNAME field the first does not.
    /// Skipping that field wrong is the failure this suite exists to catch.
    private static let plain = "H4sIAAAAAAAAA8tIzcnJV0gsKFDITS1JLeICAL6PJSYQAAAA"
    private static let named = "H4sICIP4bGoAA3JlcG9ydC50eHQACyjKL8tMSS3iDM3LLCnmcgwI8HHlNDHiAgCsS1RKGAAAAA=="

    private static func inflate(_ base64: String) throws -> String {
        let data = try #require(Data(base64Encoded: base64))
        return try #require(String(data: try Gzip.inflate(data), encoding: .utf8))
    }

    @Test func inflatesAStreamWithNoOptionalFields() throws {
        #expect(try Self.inflate(Self.plain) == "hello app meter\n")
    }

    @Test func skipsTheFilenameField() throws {
        #expect(try Self.inflate(Self.named) == "Provider\tUnits\nAPPLE\t42\n")
    }

    @Test func rejectsSomethingThatIsNotGzip() {
        let notGzip = Data(repeating: 0x41, count: 32)
        #expect(throws: Gzip.Failure.notGzip) { try Gzip.inflate(notGzip) }
    }

    /// An error response served in place of a report is the realistic way this
    /// happens, and it must not come back as an empty report.
    @Test func rejectsATruncatedFile() throws {
        let full = try #require(Data(base64Encoded: Self.plain))
        #expect(throws: (any Error).self) { try Gzip.inflate(full.prefix(12)) }
    }

    /// A stream cut short still decodes — DEFLATE has nothing to object to —
    /// so the trailer's length is what tells a partial report from a whole one.
    @Test func rejectsAStreamThatEndedEarly() throws {
        var bytes = [UInt8](try #require(Data(base64Encoded: Self.plain)))
        bytes.removeSubrange(12..<16) // drop part of the DEFLATE stream, keep the trailer
        #expect(throws: Gzip.Failure.truncated) { try Gzip.inflate(Data(bytes)) }
    }

    /// A byte flipped inside the payload is deliberately *not* caught: the CRC
    /// goes unchecked, and TLS is what rules that case out. Pinned here so the
    /// limitation stays a decision rather than a surprise.
    @Test func doesNotNoticeDamageThatKeepsTheLength() throws {
        var bytes = [UInt8](try #require(Data(base64Encoded: Self.plain)))
        bytes[14] ^= 0xFF
        let inflated = try Gzip.inflate(Data(bytes))
        #expect(inflated.count == 16)
        #expect(String(data: inflated, encoding: .utf8) != "hello app meter\n")
    }
}
