import Foundation

// LZO1X-1 compressor and decompressor.
//
// The compressor is adapted from EPaperNFCSwift by Yoshimasa Niwa (MIT License,
// Copyright (c) 2026 Yoshimasa Niwa, https://github.com/niw/EPaperNFCSwift).
// The decompressor is written from the format description in the Linux kernel
// documentation (Documentation/lzo.txt) and exists so tests can verify the
// compressor's output byte-for-byte.

enum LZO {
    static func compress(_ data: Data) -> Data {
        let src = Array(data)
        let n = src.count
        var out = Data()

        if n == 0 {
            out.append(contentsOf: [0x11, 0x00, 0x00])
            return out
        }

        struct Match {
            let start: Int
            let length: Int
            let distance: Int
        }

        @inline(__always)
        func hash3(_ b0: UInt8, _ b1: UInt8, _ b2: UInt8) -> Int {
            let v = (UInt32(b0) << 16) | (UInt32(b1) << 8) | UInt32(b2)
            return Int((v &* 2_654_435_761) >> 16) & 0xFFFF
        }

        @inline(__always)
        func appendLengthExtension(_ value: Int, to out: inout Data) {
            var v = value
            while v > 255 {
                out.append(0)
                v -= 255
            }
            out.append(UInt8(v))
        }

        @inline(__always)
        func appendLE16(_ v: Int, to out: inout Data) {
            out.append(UInt8(v & 0xff))
            out.append(UInt8((v >> 8) & 0xff))
        }

        // state == 0 required.
        func emitLongLiteral(start: Int, end: Int, to out: inout Data) {
            let len = end - start
            precondition(len >= 4)
            if len <= 18 {
                out.append(UInt8(len - 3))
            } else {
                out.append(0x00)
                appendLengthExtension(len - 18, to: &out)
            }
            out.append(contentsOf: src[start..<end])
        }

        // Returns state after emitting the first literal run.
        func emitFirstLiteral(start: Int, end: Int, to out: inout Data) -> Int {
            let len = end - start
            precondition(len > 0)
            if len <= 3 {
                out.append(UInt8(17 + len))
                out.append(contentsOf: src[start..<end])
                return len
            } else if len <= 238 {
                out.append(UInt8(17 + len))
                out.append(contentsOf: src[start..<end])
                return 4
            } else {
                emitLongLiteral(start: start, end: end, to: &out)
                return 4
            }
        }

        // state == 4 required. Encodes a 3-byte match from 2..3KB.
        func emitM1State4(distance: Int, state: Int, to out: inout Data) {
            precondition((2049...3072).contains(distance))
            precondition((0...3).contains(state))
            let d = distance - 2049
            out.append(UInt8(((d & 0x3) << 2) | state))
            out.append(UInt8((d >> 2) & 0xff))
        }

        // Copy 3..8 bytes from <=2KB distance.
        func emitM2(length: Int, distance: Int, state: Int, to out: inout Data) {
            precondition((3...8).contains(length))
            precondition((1...2048).contains(distance))
            precondition((0...3).contains(state))

            let d = distance - 1
            let dLow3 = (d & 0x7) << 2
            let high = UInt8((d >> 3) & 0xff)

            if length <= 4 {
                let l = (length - 3) << 5
                out.append(UInt8(0x40 | l | dLow3 | state))
            } else {
                let l = (length - 5) << 5
                out.append(UInt8(0x80 | l | dLow3 | state))
            }
            out.append(high)
        }

        // Copy >=3 bytes from <=16KB distance.
        func emitM3(length: Int, distance: Int, state: Int, to out: inout Data) {
            precondition(length >= 3)
            precondition((1...16384).contains(distance))
            precondition((0...3).contains(state))

            if length <= 33 {
                out.append(UInt8(0x20 | (length - 2)))
            } else {
                out.append(0x20)
                appendLengthExtension(length - 33, to: &out)
            }

            let packed = ((distance - 1) << 2) | state
            appendLE16(packed, to: &out)
        }

        // Copy >=3 bytes from 16KB..48KB distance (excluding EOS marker distance).
        func emitM4(length: Int, distance: Int, state: Int, to out: inout Data) {
            precondition(length >= 3)
            precondition((16385...49151).contains(distance))
            precondition((0...3).contains(state))

            let h = (distance >= 32768) ? 1 : 0
            if length <= 9 {
                out.append(UInt8(0x10 | (h << 3) | (length - 2)))
            } else {
                out.append(UInt8(0x10 | (h << 3)))
                appendLengthExtension(length - 9, to: &out)
            }

            let d = distance - 16384 - (h << 14)
            let packed = (d << 2) | state
            appendLE16(packed, to: &out)
        }

        func emitMatch(length: Int, distance: Int, state: Int, previousState: Int, to out: inout Data) {
            if previousState == 4 && length == 3 && (2049...3072).contains(distance) {
                emitM1State4(distance: distance, state: state, to: &out)
                return
            }

            if length <= 8 && distance <= 2048 {
                emitM2(length: length, distance: distance, state: state, to: &out)
                return
            }

            if distance <= 16384 {
                emitM3(length: length, distance: distance, state: state, to: &out)
                return
            }

            emitM4(length: length, distance: distance, state: state, to: &out)
        }

        let maxDistance = 49_151
        let maxMatchLen = 512
        var lastPos = Array(repeating: -1, count: 1 << 16)
        var matches: [Match] = []
        var i = 0
        while i + 2 < n {
            let h = hash3(src[i], src[i + 1], src[i + 2])
            let cand = lastPos[h]
            lastPos[h] = i

            var bestLen = 0
            var bestDist = 0

            if cand >= 0 {
                let dist = i - cand
                if dist <= maxDistance,
                    src[cand] == src[i],
                    src[cand + 1] == src[i + 1],
                    src[cand + 2] == src[i + 2]
                {
                    let maxLen = min(maxMatchLen, n - i)
                    var len = 3
                    while len < maxLen && src[cand + len] == src[i + len] {
                        len += 1
                    }
                    let minUsefulLen = (dist <= 2048) ? 3 : 4
                    if len >= minUsefulLen {
                        bestLen = len
                        bestDist = dist
                    }
                }
            }

            if bestLen > 0 {
                matches.append(Match(start: i, length: bestLen, distance: bestDist))
                var k = 1
                while k < bestLen && i + k + 2 < n {
                    let hk = hash3(src[i + k], src[i + k + 1], src[i + k + 2])
                    lastPos[hk] = i + k
                    k += 1
                }
                i += bestLen
            } else {
                i += 1
            }
        }

        if matches.isEmpty {
            _ = emitFirstLiteral(start: 0, end: n, to: &out)
            out.append(contentsOf: [0x11, 0x00, 0x00])
            return out
        }

        let firstLiteralLen = matches[0].start
        precondition(firstLiteralLen > 0)
        var state = emitFirstLiteral(start: 0, end: firstLiteralLen, to: &out)

        for idx in matches.indices {
            let m = matches[idx]
            let matchEnd = m.start + m.length
            let nextStart = (idx + 1 < matches.count) ? matches[idx + 1].start : n
            let gap = nextStart - matchEnd
            precondition(gap >= 0)

            if gap <= 3 {
                emitMatch(length: m.length, distance: m.distance, state: gap, previousState: state, to: &out)
                if gap > 0 {
                    out.append(contentsOf: src[matchEnd..<(matchEnd + gap)])
                }
                state = gap
            } else {
                emitMatch(length: m.length, distance: m.distance, state: 0, previousState: state, to: &out)
                state = 0
                emitLongLiteral(start: matchEnd, end: nextStart, to: &out)
                state = 4
            }
        }

        out.append(contentsOf: [0x11, 0x00, 0x00])
        return out
    }

    enum DecompressError: Error {
        case truncated
        case badDistance
        case missingEndMarker
    }

    /// Reference LZO1X decompressor used to validate `compress`.
    static func decompress(_ data: Data) throws -> Data {
        let src = Array(data)
        var ip = 0
        var out: [UInt8] = []
        out.reserveCapacity(src.count * 4)

        func byte() throws -> UInt8 {
            guard ip < src.count else { throw DecompressError.truncated }
            defer { ip += 1 }
            return src[ip]
        }

        func le16() throws -> Int {
            let lo = Int(try byte())
            let hi = Int(try byte())
            return lo | (hi << 8)
        }

        /// Zero bytes count 255 each, then one terminating non-zero byte.
        func lengthExtension() throws -> Int {
            var total = 0
            var b = try byte()
            while b == 0 {
                total += 255
                b = try byte()
            }
            return total + Int(b)
        }

        func copyLiterals(_ count: Int) throws {
            guard ip + count <= src.count else { throw DecompressError.truncated }
            out.append(contentsOf: src[ip..<(ip + count)])
            ip += count
        }

        func copyMatch(distance: Int, length: Int) throws {
            guard distance > 0, distance <= out.count else { throw DecompressError.badDistance }
            var p = out.count - distance
            for _ in 0..<length {
                out.append(out[p])
                p += 1
            }
        }

        var state = 0

        // First byte.
        var first = try byte()
        if first == 17, src.count >= 5, src[1] == 0 {
            // Bitstream version marker: skip the version byte.
            _ = try byte()
            first = try byte()
        }
        if first > 17 {
            let t = Int(first) - 17
            try copyLiterals(t)
            state = t < 4 ? t : 4
        } else {
            ip -= 1
        }

        while true {
            let op = Int(try byte())
            var length = 0
            var distance = 0
            var s = 0

            if op >= 128 {
                length = 5 + ((op >> 5) & 3)
                let h = Int(try byte())
                distance = (h << 3) + ((op >> 2) & 7) + 1
                s = op & 3
            } else if op >= 64 {
                length = 3 + ((op >> 5) & 1)
                let h = Int(try byte())
                distance = (h << 3) + ((op >> 2) & 7) + 1
                s = op & 3
            } else if op >= 32 {
                let l = op & 31
                length = 2 + (l != 0 ? l : 31 + (try lengthExtension()))
                let le = try le16()
                distance = (le >> 2) + 1
                s = le & 3
            } else if op >= 16 {
                let h = (op >> 3) & 1
                let l = op & 7
                length = 2 + (l != 0 ? l : 7 + (try lengthExtension()))
                let le = try le16()
                distance = 16384 + (h << 14) + (le >> 2)
                s = le & 3
                if distance == 16384 {
                    return Data(out)  // End of stream.
                }
            } else {
                switch state {
                case 0:
                    let l = op & 15
                    length = l != 0 ? l + 3 : 18 + (try lengthExtension())
                    try copyLiterals(length)
                    state = 4
                    continue
                case 1...3:
                    let h = Int(try byte())
                    distance = (h << 2) + ((op >> 2) & 3) + 1
                    length = 2
                    s = op & 3
                default:
                    let h = Int(try byte())
                    distance = (h << 2) + ((op >> 2) & 3) + 2049
                    length = 3
                    s = op & 3
                }
            }

            try copyMatch(distance: distance, length: length)
            if s > 0 {
                try copyLiterals(s)
            }
            state = s
        }
    }
}
