import Foundation

/// 只读的最小 ZIP 解析器：从中央目录里读出条目，按需解压。
/// 用来在 App 内直接打开发票 / 账单导出的 xlsx（xlsx 本质就是一个 zip）。
enum ZipArchive {

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    struct Entry {
        let name: String
        let method: Int
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
    }

    // MARK: - 读中央目录

    static func entries(in data: Data) throws -> [Entry] {
        let bytes = [UInt8](data)
        guard let eocd = findEndOfCentralDirectory(bytes) else {
            throw Failure(message: "这不是一个 zip/xlsx 文件（找不到目录区）")
        }

        let total = Int(readUInt16(bytes, eocd + 10))
        var offset = Int(readUInt32(bytes, eocd + 16))
        var result: [Entry] = []
        result.reserveCapacity(total)

        for _ in 0..<total {
            guard offset + 46 <= bytes.count, readUInt32(bytes, offset) == 0x02014B50 else {
                break
            }
            let method = Int(readUInt16(bytes, offset + 10))
            let compressedSize = Int(readUInt32(bytes, offset + 20))
            let uncompressedSize = Int(readUInt32(bytes, offset + 24))
            let nameLength = Int(readUInt16(bytes, offset + 28))
            let extraLength = Int(readUInt16(bytes, offset + 30))
            let commentLength = Int(readUInt16(bytes, offset + 32))
            let localOffset = Int(readUInt32(bytes, offset + 42))

            let nameStart = offset + 46
            guard nameStart + nameLength <= bytes.count else { break }
            let nameData = Data(bytes[nameStart..<(nameStart + nameLength)])
            let name = String(data: nameData, encoding: .utf8)
                ?? String(data: nameData, encoding: .isoLatin1)
                ?? ""

            result.append(Entry(
                name: name,
                method: method,
                compressedSize: compressedSize,
                uncompressedSize: uncompressedSize,
                localHeaderOffset: localOffset
            ))

            offset = nameStart + nameLength + extraLength + commentLength
        }

        guard !result.isEmpty else {
            throw Failure(message: "zip 目录是空的")
        }
        return result
    }

    // MARK: - 解压单个条目

    static func extract(_ entry: Entry, from data: Data) throws -> Data {
        let bytes = [UInt8](data)
        let header = entry.localHeaderOffset
        guard header + 30 <= bytes.count, readUInt32(bytes, header) == 0x04034B50 else {
            throw Failure(message: "条目「\(entry.name)」的本地头损坏")
        }

        let nameLength = Int(readUInt16(bytes, header + 26))
        let extraLength = Int(readUInt16(bytes, header + 28))
        let start = header + 30 + nameLength + extraLength
        guard start + entry.compressedSize <= bytes.count else {
            throw Failure(message: "条目「\(entry.name)」的数据被截断")
        }

        let payload = Data(bytes[start..<(start + entry.compressedSize)])
        switch entry.method {
        case 0:
            return payload
        case 8:
            return try Inflate.decompress(payload)
        default:
            throw Failure(message: "不支持的压缩方式（\(entry.method)）")
        }
    }

    /// 按名字取文件内容
    static func file(named name: String, in data: Data) throws -> Data? {
        let all = try entries(in: data)
        guard let entry = all.first(where: { $0.name == name }) else { return nil }
        return try extract(entry, from: data)
    }

    // MARK: - 小工具

    private static func findEndOfCentralDirectory(_ bytes: [UInt8]) -> Int? {
        guard bytes.count >= 22 else { return nil }
        let limit = max(0, bytes.count - 22 - 65_535)
        var index = bytes.count - 22
        while index >= limit {
            if readUInt32(bytes, index) == 0x06054B50 {
                return index
            }
            index -= 1
        }
        return nil
    }

    private static func readUInt16(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
        guard offset + 1 < bytes.count else { return 0 }
        return UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }

    private static func readUInt32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        guard offset + 3 < bytes.count else { return 0 }
        return UInt32(bytes[offset])
            | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16)
            | (UInt32(bytes[offset + 3]) << 24)
    }
}
