import Foundation

/// 极简的原始 DEFLATE（RFC 1951）解码器。
///
/// 只为了一件小事服务：App 里没有第三方库，又要能读 xlsx（xlsx 就是个 zip，
/// 里面是 deflate 压缩的 XML）。写法和 zlib 的 puff 一致：Huffman 规范码表 +
/// stored / fixed / dynamic 三种块。
enum Inflate {

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func decompress(_ input: Data) throws -> Data {
        var state = State(input: [UInt8](input))
        try state.run()
        return Data(state.output)
    }

    // MARK: - 长度 / 距离表

    private static let lengthBase: [Int] = [
        3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31,
        35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258
    ]

    private static let lengthExtra: [Int] = [
        0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2,
        3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0
    ]

    private static let distBase: [Int] = [
        1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193,
        257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577
    ]

    private static let distExtra: [Int] = [
        0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6,
        7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13
    ]

    private static let codeLengthOrder: [Int] = [
        16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15
    ]

    // MARK: - Huffman 表

    private struct Huffman {
        var counts: [Int]
        var symbols: [Int]
    }

    // MARK: - 解码状态

    private struct State {
        private let input: [UInt8]
        private var position = 0
        private var bitBuffer = 0
        private var bitCount = 0
        private(set) var output: [UInt8] = []

        init(input: [UInt8]) {
            self.input = input
        }

        mutating func run() throws {
            var isFinal = false
            var guardCount = 0
            while !isFinal {
                guardCount += 1
                if guardCount > 100_000 {
                    throw Inflate.Failure(message: "压缩数据块过多，可能文件已损坏")
                }
                isFinal = try bits(1) == 1
                let type = try bits(2)
                switch type {
                case 0:
                    try storedBlock()
                case 1:
                    try codes(fixed: true)
                case 2:
                    try codes(fixed: false)
                default:
                    throw Inflate.Failure(message: "压缩块类型不支持（3）")
                }
            }
        }

        // MARK: 读位

        private mutating func bits(_ need: Int) throws -> Int {
            var value = bitBuffer
            while bitCount < need {
                guard position < input.count else {
                    throw Inflate.Failure(message: "压缩数据提前结束")
                }
                value |= Int(input[position]) << bitCount
                position += 1
                bitCount += 8
            }
            bitBuffer = value >> need
            bitCount -= need
            return value & ((1 << need) - 1)
        }

        private mutating func alignToByte() {
            bitBuffer = 0
            bitCount = 0
        }

        // MARK: 三种块

        private mutating func storedBlock() throws {
            alignToByte()
            guard position + 4 <= input.count else {
                throw Inflate.Failure(message: "stored 块头不完整")
            }
            let length = Int(input[position]) | (Int(input[position + 1]) << 8)
            let inverse = Int(input[position + 2]) | (Int(input[position + 3]) << 8)
            position += 4
            guard (length ^ 0xFFFF) == inverse else {
                throw Inflate.Failure(message: "stored 块长度校验失败")
            }
            guard position + length <= input.count else {
                throw Inflate.Failure(message: "stored 块数据不足")
            }
            output.append(contentsOf: input[position..<(position + length)])
            position += length
        }

        private mutating func codes(fixed: Bool) throws {
            var literalLengths = [Int](repeating: 0, count: 288)
            var distanceLengths = [Int](repeating: 0, count: 30)

            if fixed {
                for symbol in 0...287 {
                    if symbol < 144 {
                        literalLengths[symbol] = 8
                    } else if symbol < 256 {
                        literalLengths[symbol] = 9
                    } else if symbol < 280 {
                        literalLengths[symbol] = 7
                    } else {
                        literalLengths[symbol] = 8
                    }
                }
                for symbol in 0..<30 {
                    distanceLengths[symbol] = 5
                }
            } else {
                let literalCount = try bits(5) + 257
                let distanceCount = try bits(5) + 1
                let codeLengthCount = try bits(4) + 4

                var codeLengths = [Int](repeating: 0, count: 19)
                for index in 0..<codeLengthCount {
                    codeLengths[Inflate.codeLengthOrder[index]] = try bits(3)
                }
                let codeLengthTable = try buildTable(codeLengths)

                var lengths: [Int] = []
                lengths.reserveCapacity(literalCount + distanceCount)
                while lengths.count < literalCount + distanceCount {
                    let symbol = try decode(codeLengthTable)
                    switch symbol {
                    case 0...15:
                        lengths.append(symbol)
                    case 16:
                        guard let last = lengths.last else {
                            throw Inflate.Failure(message: "长度码 16 没有前一项")
                        }
                        let repeatCount = try bits(2) + 3
                        lengths.append(contentsOf: [Int](repeating: last, count: repeatCount))
                    case 17:
                        let repeatCount = try bits(3) + 3
                        lengths.append(contentsOf: [Int](repeating: 0, count: repeatCount))
                    case 18:
                        let repeatCount = try bits(7) + 11
                        lengths.append(contentsOf: [Int](repeating: 0, count: repeatCount))
                    default:
                        throw Inflate.Failure(message: "长度码超出范围")
                    }
                }
                guard lengths.count == literalCount + distanceCount else {
                    throw Inflate.Failure(message: "长度表不完整")
                }

                literalLengths = Array(lengths[0..<literalCount])
                distanceLengths = Array(lengths[literalCount..<(literalCount + distanceCount)])
            }

            let literalTable = try buildTable(literalLengths)
            let distanceTable = try buildTable(distanceLengths)
            try inflateBlock(literal: literalTable, distance: distanceTable)
        }

        private mutating func inflateBlock(literal: Huffman, distance: Huffman) throws {
            while true {
                let symbol = try decode(literal)
                if symbol < 256 {
                    output.append(UInt8(symbol))
                    continue
                }
                if symbol == 256 {
                    return
                }

                let lengthIndex = symbol - 257
                guard lengthIndex >= 0, lengthIndex < Inflate.lengthBase.count else {
                    throw Inflate.Failure(message: "长度符号超出范围")
                }
                let length = Inflate.lengthBase[lengthIndex] + (try bits(Inflate.lengthExtra[lengthIndex]))

                let distanceSymbol = try decode(distance)
                guard distanceSymbol >= 0, distanceSymbol < Inflate.distBase.count else {
                    throw Inflate.Failure(message: "距离符号超出范围")
                }
                let back = Inflate.distBase[distanceSymbol] + (try bits(Inflate.distExtra[distanceSymbol]))
                guard back > 0, back <= output.count else {
                    throw Inflate.Failure(message: "距离超出了已解压范围")
                }

                var start = output.count - back
                for _ in 0..<length {
                    output.append(output[start])
                    start += 1
                }
            }
        }

        // MARK: 建表 / 解一个符号

        private func buildTable(_ lengths: [Int]) throws -> Huffman {
            var counts = [Int](repeating: 0, count: 16)
            for length in lengths where length > 0 {
                counts[length] += 1
            }

            var left = 1
            for length in 1...15 {
                left <<= 1
                left -= counts[length]
                if left < 0 {
                    throw Inflate.Failure(message: "Huffman 码表超额")
                }
            }

            var offsets = [Int](repeating: 0, count: 16)
            for length in 1..<15 {
                offsets[length + 1] = offsets[length] + counts[length]
            }

            var symbols = [Int](repeating: 0, count: lengths.count)
            for (symbol, length) in lengths.enumerated() where length > 0 {
                symbols[offsets[length]] = symbol
                offsets[length] += 1
            }

            return Huffman(counts: counts, symbols: symbols)
        }

        private mutating func decode(_ table: Huffman) throws -> Int {
            var code = 0
            var first = 0
            var index = 0
            for length in 1...15 {
                code |= try bits(1)
                let count = table.counts[length]
                if code - count < first {
                    return table.symbols[index + (code - first)]
                }
                index += count
                first = (first + count) << 1
                code <<= 1
            }
            throw Inflate.Failure(message: "Huffman 码无效")
        }
    }
}
