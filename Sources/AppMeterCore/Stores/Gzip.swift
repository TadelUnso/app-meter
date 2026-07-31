import Compression
import Foundation

/// Unwraps the gzip that App Store Connect serves sales reports in.
///
/// Foundation has no gzip, and the system's Compression framework speaks raw
/// DEFLATE rather than the gzip container — so the container is peeled here and
/// the payload handed to the framework. That is the whole reason this file
/// exists; it is not a general-purpose compression layer, and it only decodes.
public enum Gzip {
    public enum Failure: LocalizedError {
        case notGzip
        case truncated
        case corrupt

        public var errorDescription: String? {
            switch self {
            case .notGzip: "The report is not a gzip file."
            case .truncated: "The report ended in the middle of its header."
            case .corrupt: "The report could not be decompressed."
            }
        }
    }

    public static func inflate(_ data: Data) throws -> Data {
        let bytes = [UInt8](data)
        let inflated = try rawInflate(try deflateBody(of: bytes))

        // The trailer's ISIZE against what actually came out. This catches a
        // stream that stopped early — an error page or a dropped connection
        // served in place of a report — which DEFLATE alone will happily
        // decode into a short, plausible-looking file.
        guard UInt32(truncatingIfNeeded: inflated.count) == expandedSize(of: bytes) else {
            throw Failure.truncated
        }
        return inflated
    }

    /// Little-endian, last four bytes, modulo 2^32 by definition.
    private static func expandedSize(of bytes: [UInt8]) -> UInt32 {
        bytes.suffix(4).reversed().reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }

    /// RFC 1952 §2.3: ten fixed bytes, then whichever optional fields the flag
    /// byte announces, then the DEFLATE stream, then an eight-byte trailer.
    private static func deflateBody(of bytes: [UInt8]) throws -> [UInt8] {
        guard bytes.count >= 18 else { throw Failure.truncated }
        guard bytes[0] == 0x1f, bytes[1] == 0x8b else { throw Failure.notGzip }
        // The only compression method gzip has ever defined is DEFLATE.
        guard bytes[2] == 0x08 else { throw Failure.corrupt }

        let flags = bytes[3]
        var index = 10

        if flags & 0x04 != 0 { // FEXTRA: two length bytes, little-endian
            guard index + 2 <= bytes.count else { throw Failure.truncated }
            index += 2 + Int(bytes[index]) | Int(bytes[index + 1]) << 8
        }
        if flags & 0x08 != 0 { index = try skipCString(in: bytes, from: index) } // FNAME
        if flags & 0x10 != 0 { index = try skipCString(in: bytes, from: index) } // FCOMMENT
        if flags & 0x02 != 0 { index += 2 } // FHCRC

        // The trailer is CRC32 then the uncompressed size. Only the size is
        // checked, by the caller. The CRC is not: TLS already authenticates the
        // bytes end to end, so the case it would add cover for — damage that
        // still decodes and still has the right length — cannot arise here.
        let end = bytes.count - 8
        guard index < end else { throw Failure.truncated }
        return Array(bytes[index..<end])
    }

    private static func skipCString(in bytes: [UInt8], from start: Int) throws -> Int {
        var index = start
        while index < bytes.count, bytes[index] != 0 { index += 1 }
        guard index < bytes.count else { throw Failure.truncated }
        return index + 1
    }

    /// COMPRESSION_ZLIB is Apple's name for raw DEFLATE — no zlib header, which
    /// is exactly what sits inside a gzip container.
    private static func rawInflate(_ body: [UInt8]) throws -> Data {
        var stream = compression_stream(
            dst_ptr: UnsafeMutablePointer<UInt8>.allocate(capacity: 0),
            dst_size: 0,
            src_ptr: UnsafePointer<UInt8>(UnsafeMutablePointer<UInt8>.allocate(capacity: 0)),
            src_size: 0,
            state: nil
        )
        guard compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB)
            == COMPRESSION_STATUS_OK
        else { throw Failure.corrupt }
        defer { compression_stream_destroy(&stream) }

        let capacity = 64 * 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
        defer { buffer.deallocate() }

        var output = Data()
        return try body.withUnsafeBufferPointer { source in
            guard let base = source.baseAddress else { throw Failure.corrupt }
            stream.src_ptr = base
            stream.src_size = source.count

            while true {
                stream.dst_ptr = buffer
                stream.dst_size = capacity

                switch compression_stream_process(&stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue)) {
                case COMPRESSION_STATUS_OK:
                    output.append(buffer, count: capacity - stream.dst_size)
                case COMPRESSION_STATUS_END:
                    output.append(buffer, count: capacity - stream.dst_size)
                    return output
                default:
                    throw Failure.corrupt
                }
            }
        }
    }
}
