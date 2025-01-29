import Foundation

public enum QOIError: Error {
    case invalidDimensions(width: UInt32, height: UInt32)
}

public enum QOIColorSpace: UInt8 {
    case sRGB
    case linear
}

public struct QOIDescription {
    public var width: UInt32
    public var height: UInt32
    public var channels: UInt8
    public var colorSpace: QOIColorSpace

    public init(width: UInt32, height: UInt32, includesAlpha: Bool, colorSpace: QOIColorSpace) throws {
        guard width > 0 && height > 0 else {
            throw QOIError.invalidDimensions(width: width, height: height)
        }

        guard height < (maximumPixelSize / width) else {
            throw QOIError.invalidDimensions(width: width, height: height)
        }

        self.width = width
        self.height = height
        self.channels = includesAlpha ? 4 : 3
        self.colorSpace = colorSpace
    }
}

@usableFromInline
enum Operation: UInt8 {
    case index = 0x00 /* 00xxxxxx */
    case diff = 0x40 /* 01xxxxxx */
    case luma = 0x80 /* 10xxxxxx */
    case run = 0xc0 /* 11xxxxxx */
    case rgb = 0xfe /* 11111110 */
    case rgba = 0xff /* 11111111 */
}

@usableFromInline
struct Color: Equatable {
    @usableFromInline
    var r: UInt8

    @usableFromInline
    var g: UInt8

    @usableFromInline
    var b: UInt8

    @usableFromInline
    var a: UInt8

    @inlinable
    init(r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    @inlinable
    static var black: Color {
        Color(r: 0, g: 0, b: 0, a: .max)
    }

    @inlinable
    var hash: Int32 {
        Int32(r) * 3 + Int32(g) * 5 + Int32(b) * 7 + Int32(a) * 11
    }

    @inlinable
    static func ==(lhs: Color, rhs: Color) -> Bool {
        withUnsafeBytes(of: lhs) { lhsP in
            withUnsafeBytes(of: rhs) { rhsP in
                memcmp(lhsP.baseAddress!, rhsP.baseAddress!, MemoryLayout<Color>.size) != 0
            }
        }
    }
}

@usableFromInline
var magicHeader: UInt32 {
    (UInt32(UInt8(ascii: "q")) << 24 | UInt32(UInt8(ascii: "o")) << 16 |
     UInt32(UInt8(ascii: "i")) <<  8 | UInt32(UInt8(ascii: "f")))
}

@usableFromInline
let headerSize: UInt32 = 14

/* 2GB is the max file size that this implementation can safely handle. We guard
against anything larger than that, assuming the worst case with 5 bytes per
pixel, rounded down to a nice clean value. 400 million pixels ought to be
enough for anybody. */
let maximumPixelSize: UInt32 = 400_000_000

@usableFromInline
let paddingLength: UInt32 = 8

@usableFromInline
let padding: [UInt8] = [0, 0, 0, 0, 0, 0, 0, 1]

@inlinable
func write(_ int: UInt32, to bytes: UnsafeMutableRawPointer, at offset: inout Int) {
    bytes.storeBytes(of: int.bigEndian, toByteOffset: offset, as: UInt32.self)
    offset &+= MemoryLayout<UInt32>.size
}

@inlinable
func write(_ byte: UInt8, to bytes: UnsafeMutableRawPointer, at offset: inout Int) {
    bytes.storeBytes(of: byte, toByteOffset: offset, as: UInt8.self)
    offset &+= 1
}

@inlinable
public func qoiEncode<Pixels: Collection>(
    _ pixels: Pixels,
    description: QOIDescription
) -> [UInt8] where Pixels.Element == UInt8, Pixels.Index == Int {
    let maximumSize = description.width * description.height * UInt32(description.channels + 1) + headerSize + paddingLength
    return [UInt8](unsafeUninitializedCapacity: Int(maximumSize)) { buffer, initializedCount in
        initializedCount = qoiEncode(into: buffer, pixels: pixels, description: description)
    }
}

extension Collection where Element == UInt8 {
    @inlinable
    func qoiData(description: QOIDescription) -> [UInt8] {
        withContiguousStorageIfAvailable { buffer in
            qoiEncode(buffer, description: description)
        } ?? []
    }
}

@inlinable
func qoiEncode<Pixels: Collection>(
    into buffer: UnsafeMutableBufferPointer<UInt8>,
    pixels: Pixels,
    index: UnsafeMutablePointer<Color>,
    description: QOIDescription
) -> Int where Pixels.Element == UInt8, Pixels.Index == Int {
    let bytes = UnsafeMutableRawPointer(buffer.baseAddress!)
    var px = Color.black
    var prevPx = Color.black

    var p = 0
    write(magicHeader, to: bytes, at: &p)
    write(description.width, to: bytes, at: &p)
    write(description.height, to: bytes, at: &p)
    write(description.channels, to: bytes, at: &p)
    write(description.colorSpace.rawValue, to: bytes, at: &p)

    var run: UInt32 = 0

    let px_end = pixels.count - Int(description.channels)
    let channels = description.channels

    for px_pos in stride(from: 0, to: pixels.count, by: Int(channels)) {
        defer {
            prevPx = px
        }

        px.r = pixels[px_pos]
        px.g = pixels[px_pos + 1]
        px.b = pixels[px_pos + 2]

        if channels == 4 {
            px.a = pixels[px_pos + 3]
        }

        if px == prevPx {
            run += 1
            if run == 62 || px_pos == px_end {
                write(Operation.run.rawValue | UInt8(run - 1), to: bytes, at: &p)
                run = 0
            }
            continue
        }

        var index_pos: Int = 0

        if run > 0 {
            write(Operation.run.rawValue | UInt8(run - 1), to: bytes, at: &p)
            run = 0
        }

        index_pos = Int(px.hash % 64)

        if index[index_pos] == px {
            write(Operation.index.rawValue | UInt8(index_pos), to: bytes, at: &p)
            continue
        }

        index[index_pos] = px

        if px.a != prevPx.a {
            write(Operation.rgba.rawValue, to: bytes, at: &p)
            write(px.r, to: bytes, at: &p)
            write(px.g, to: bytes, at: &p)
            write(px.b, to: bytes, at: &p)
            write(px.a, to: bytes, at: &p)
        }

        let vr = Int16(px.r) - Int16(prevPx.r)
        let vg = Int16(px.g) - Int16(prevPx.g)
        let vb = Int16(px.b) - Int16(prevPx.b)

        let vg_r = vr - vg
        let vg_b = vb - vg

        if
            vr > -3 && vr < 2 &&
                vg > -3 && vg < 2 &&
                vb > -3 && vb < 2
        {
            write(Operation.diff.rawValue | UInt8(vr + 2) << 4 | UInt8(vg + 2) << 2 | UInt8(vb + 2), to: bytes, at: &p)
        }
        else if (
            vg_r >  -9 && vg_r <  8 &&
            vg   > -33 && vg   < 32 &&
            vg_b >  -9 && vg_b <  8
        ) {
            write(Operation.luma.rawValue | UInt8(vg + 32), to: bytes, at: &p)
            write(UInt8(vg_r + 8) << 4 | UInt8(vg_b + 8), to: bytes, at: &p)
        }
        else {
            write(Operation.rgb.rawValue, to: bytes, at: &p)
            write(px.r, to: bytes, at: &p)
            write(px.g, to: bytes, at: &p)
            write(px.b, to: bytes, at: &p)
        }
    }

    for paddingByte in padding {
        write(paddingByte, to: bytes, at: &p)
    }

    return p
}

@inlinable
func qoiEncode<Pixels: Collection, Buffer: MutableCollection>(
    into buffer: Buffer,
    pixels: Pixels,
    description: QOIDescription
) -> Int where Pixels.Element == UInt8, Pixels.Index == Int, Buffer.Element == UInt8, Buffer.Index == Int {
    var buffer = buffer
    return buffer.withContiguousMutableStorageIfAvailable { bufferStorage in
        withUnsafeTemporaryAllocation(of: Color.self, capacity: 64) { indexBuf in
            indexBuf.initialize(repeating: Color(r: 0, g: 0, b: 0, a: 0))
            return qoiEncode(into: bufferStorage, pixels: pixels, index: indexBuf.baseAddress!, description: description)
        }
    }!
}
