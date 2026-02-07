import Foundation
import Compression

extension Data {
    func gunzipped() -> Data? {
        return decompressGzip()
    }

    private func decompressGzip() -> Data? {
        let bufferSize = 64 * 1024
        var destination = Data()
        let scratch = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { scratch.deallocate() }

        return withUnsafeBytes { rawBuffer -> Data? in
            guard let baseAddress = rawBuffer.bindMemory(to: UInt8.self).baseAddress else { return nil }
            var stream = compression_stream(
                dst_ptr: UnsafeMutablePointer<UInt8>.allocate(capacity: 1),
                dst_size: 0,
                src_ptr: baseAddress,
                src_size: count,
                state: nil
            )
            stream.dst_ptr.deallocate()
            var status = compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB)
            guard status != COMPRESSION_STATUS_ERROR else { return nil }
            defer { compression_stream_destroy(&stream) }

            repeat {
                stream.dst_ptr = scratch
                stream.dst_size = bufferSize
                status = compression_stream_process(&stream, 0)
                let produced = bufferSize - stream.dst_size
                if produced > 0 {
                    destination.append(scratch, count: produced)
                }
            } while status == COMPRESSION_STATUS_OK

            if status == COMPRESSION_STATUS_END {
                return destination
            }
            return nil
        }
    }
}
