import XCTest
import Cmurmur3
@testable import Filters

/// existential 派发 vs 免派发机制的微基准。
///
/// 同样的 MurmurHash3_x86_32 计算（同一 buffer、同一 seed），仅改变派发方式：
///   1. 直接静态调用（对照基线）
///   2. any Hasher existential（witness 表 + 间接调用 + 额外调用层）
///   3. enum 闭集 switch（分支 + 直接调用）
///   4. @convention(c) 函数指针（手写 vtable：一次间接调用，无 witness）
///   5. Swift thick closure（手写 vtable 的 Swift 风味：间接调用 + context 加载）
final class DispatchMicroBenchmarks: XCTestCase {

  private let bytes: [UInt8] = Array("https://example.com/catalog/items/page/123456/detail?ref=feed".utf8)
  private let iterations = 1_000_000

  /// 与 BloomFilter 内部快速路径相同的闭集形状（含 custom 兜底 case）
  private enum HashImpl {
    case murmur3
    case xxh32
    case custom(any Hasher)
  }

  /// 手写 vtable：C 约定函数指针
  private struct CVTable {
    let hash: @convention(c) (_ bytes: UnsafeRawPointer?, _ count: Int, _ seed: UInt32) -> UInt32
  }

  func testBench1DirectStaticCall() {
    measure {
      bytes.withUnsafeBufferPointer { buf in
        let raw = UnsafeRawBufferPointer(buf)
        var acc: Int64 = 0
        for _ in 0..<iterations {
          acc &+= Int64(MurmurHash3.x86_32(raw, seed: 7))
        }
        if acc == 0 { XCTFail() }
      }
    }
  }

  func testBench2Existential() {
    let hasher: any Hasher = DefaultHasher()
    measure {
      bytes.withUnsafeBufferPointer { buf in
        let raw = UnsafeRawBufferPointer(buf)
        var acc: Int64 = 0
        for _ in 0..<iterations {
          let hash = hasher.hashValues(raw, seed: 7)
          acc &+= Int64(hash)
        }
        if acc == 0 { XCTFail() }
      }
    }
  }

  func testBench3EnumSwitch() {
    let impl = HashImpl.murmur3 // 活跃 case 为 murmur3 快速路径（含 custom case 的三值闭集）
    measure {
      bytes.withUnsafeBufferPointer { buf in
        let raw = UnsafeRawBufferPointer(buf)
        var acc: Int64 = 0
        for _ in 0..<iterations {
          switch impl {
          case .murmur3:
            acc &+= Int64(MurmurHash3.x86_32(raw, seed: 7))
          case .xxh32:
            acc &+= Int64(XXH.xxh32(raw, seed: 7))
          case .custom(let hasher):
            let hash = hasher.hashValues(raw, seed: 7)
            acc &+= Int64(hash)
          }
        }
        if acc == 0 { XCTFail() }
      }
    }
  }

  func testBench4ConventionCPointer() {
    let vtable = CVTable { ptr, count, seed in
      var out: UInt32 = 0
      MurmurHash3_x86_32(ptr, Int32(count), seed, &out)
      return out
    }
    measure {
      bytes.withUnsafeBufferPointer { buf in
        var acc: Int64 = 0
        for _ in 0..<iterations {
          acc &+= Int64(vtable.hash(buf.baseAddress, buf.count, 7))
        }
        if acc == 0 { XCTFail() }
      }
    }
  }

  func testBench5SwiftClosure() {
    let hash: (UnsafeRawBufferPointer, UInt32) -> UInt32 = { buffer, seed in
      MurmurHash3.x86_32(buffer, seed: seed)
    }
    measure {
      bytes.withUnsafeBufferPointer { buf in
        let raw = UnsafeRawBufferPointer(buf)
        var acc: Int64 = 0
        for _ in 0..<iterations {
          acc &+= Int64(hash(raw, 7))
        }
        if acc == 0 { XCTFail() }
      }
    }
  }

  // MARK: - Bitmap 派发对照（同样的病，第二处）

  func testBench6BitmapExistentialGet() {
    let bitmap: any Bitmap = CompressedBitmap(400_000)
    bitmap.set(value: true, for: 123_456)
    measure {
      var acc = 0
      for _ in 0..<iterations {
        if let b = bitmap.get(for: 123_456) { acc &+= b ? 1 : 0 }
      }
      if acc != iterations { XCTFail() }
    }
  }

  func testBench7BitmapConcreteGet() {
    let bitmap = CompressedBitmap(400_000)
    bitmap.set(value: true, for: 123_456)
    measure {
      var acc = 0
      for _ in 0..<iterations {
        if let b = bitmap.get(for: 123_456) { acc &+= b ? 1 : 0 }
      }
      if acc != iterations { XCTFail() }
    }
  }

}
