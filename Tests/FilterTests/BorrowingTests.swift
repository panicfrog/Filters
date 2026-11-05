import XCTest
@testable import Filters

/// 作用域借用（zero-copy）路径的正确性测试
final class BorrowingTests: XCTestCase {

  // MARK: - FilterElement.withUnsafeBytes

  func testStringWithUnsafeBytesContent() {
    let cases = [
      "",
      "hello",                                             // 小字符串（内联存储）
      "https://example.com/items/1234567890/item",         // 大字符串（堆存储）
      "你好世界，这是一段足够长的中文字符串，肯定需要堆存储来放置它！",  // 非 ASCII
    ]
    for s in cases {
      let borrowed = s.withUnsafeBytes { Array($0) }
      XCTAssertEqual(borrowed, Array(s.utf8), "borrowed bytes mismatch")
    }
  }

  func testDataElementWithUnsafeBytes() {
    let d = Data([0xff, 0x01, 0x80, 0x7f])
    let borrowed = d.withUnsafeBytes { Array($0) }
    XCTAssertEqual(borrowed, [0xff, 0x01, 0x80, 0x7f])
  }

  /// 只实现了 data() 的自定义 conformer：应通过默认桥接实现正常工作
  private struct RawElement: FilterElement {
    let bytes: [UInt8]
    func data() -> Data { Data(bytes) }
  }

  func testCustomFilterElementViaDataBridge() {
    let bloom = BloomFilterBuilder.default.with(maxElements: 100).build()
    let element = RawElement(bytes: Array("custom element".utf8))
    bloom.add(element)
    XCTAssertTrue(bloom.contains(element))
    XCTAssertFalse(bloom.contains(RawElement(bytes: Array("something else".utf8))))
  }

  // MARK: - Hasher 借用版本与 Data 版本一致性

  private func checkHashEquality<H: Hasher>(_ hasher: H) where H.I == UInt32 {
    let strings = [
      "",
      "a",
      "hello, world",
      "你好世界，filter borrowing 测试",
      "https://github.com/panicfrog/Filters/blob/main/README.md",
    ]
    for s in strings {
      let data = Data(s.utf8)
      for seed: UInt32 in 0...7 {
        let viaData = hasher.hashValues(data, seed: seed)
        let viaBuffer = s.withUnsafeBytes { hasher.hashValues($0, seed: seed) }
        XCTAssertEqual(viaBuffer, viaData, "seed=\(seed), string=\(s)")
      }
    }
  }

  func testBufferHashMatchesDataHash() {
    checkHashEquality(DefaultHasher())
    checkHashEquality(Xxhasher())
  }

  func testMurmurBufferOverloads() {
    let s = "The quick brown fox jumps over the lazy dog"
    let data = Data(s.utf8)
    for seed: UInt32 in [0, 1, 42] {
      let expected = MurmurHash3.x64_128(data, seed: seed)
      let actual = s.withUnsafeBytes { MurmurHash3.x64_128($0, seed: seed) }
      XCTAssertEqual(actual, expected)

      let expected128 = MurmurHash3.x86_128(data, seed: seed)
      let actual128 = s.withUnsafeBytes { MurmurHash3.x86_128($0, seed: seed) }
      XCTAssertEqual(actual128, expected128)
    }
  }

  func testXXHBufferOverloads() {
    let s = "The quick brown fox jumps over the lazy dog"
    let data = Data(s.utf8)
    for seed: UInt32 in [0, 1, 42] {
      let expected32 = XXH.xxh32(data, seed: seed)
      let actual32 = s.withUnsafeBytes { XXH.xxh32($0, seed: seed) }
      XCTAssertEqual(actual32, expected32)

      let expected64 = XXH.xxh64(data, seed: UInt64(seed))
      let actual64 = s.withUnsafeBytes { XXH.xxh64($0, seed: UInt64(seed)) }
      XCTAssertEqual(actual64, expected64)
    }
  }

  // MARK: - 过滤器端到端

  func testEmptyStringElement() {
    let bloom = BloomFilterBuilder.default.with(maxElements: 10).build()
    bloom.add("")
    XCTAssertTrue(bloom.contains(""))
    XCTAssertFalse(bloom.contains("x"))
  }

  func testDataElementThroughFilter() {
    let bloom = BloomFilterBuilder.default.with(maxElements: 100).build()
    let element = Data("data element".utf8)
    bloom.add(element)
    XCTAssertTrue(bloom.contains(element))
    XCTAssertFalse(bloom.contains(Data("other".utf8)))
  }

  func testBloomFilterBehaviorUnchanged() {
    // 与旧实现相同的判定语义：全部命中位为 1 才返回 true
    let bloom = BloomFilter(hashCount: 14,
                            bitmap: CompressedBitmap(200_000),
                            hasher: DefaultHasher())
    for i in 0..<1_000 {
      bloom.add("element-\(i)")
    }
    for i in 0..<1_000 {
      XCTAssertTrue(bloom.contains("element-\(i)"))
    }
    var falsePositives = 0
    for i in 1_000..<2_000 {
      if bloom.contains("element-\(i)") { falsePositives += 1 }
    }
    // k=14, m/n=200 时误报率应远小于 1e-4（1000 次查询期望 0 次）
    XCTAssertEqual(falsePositives, 0)
  }

  // MARK: - 免派发快速路径归一化后的 .custom 兜底

  /// 自定义 hasher（FNV-1a）：应走 .custom existential 路径且行为正确
  private struct CustomFNVHasher: Hasher {
    typealias I = UInt32
    func hashValues(_ data: Data, seed: UInt32) -> UInt32 {
      var hash: UInt32 = 2166136261 ^ seed
      for byte in data {
        hash = (hash ^ UInt32(byte)) &* 16777619
      }
      return hash
    }
  }

  func testCustomHasherPath() {
    let bloom = BloomFilter(hashCount: 6,
                            bitmap: CompressedBitmap(100_000),
                            hasher: CustomFNVHasher())
    for i in 0..<500 {
      bloom.add("custom-hasher-\(i)")
    }
    for i in 0..<500 {
      XCTAssertTrue(bloom.contains("custom-hasher-\(i)"))
    }
    XCTAssertFalse(bloom.contains("not-present"))
  }

  /// 自定义 bitmap（[UInt8] 存储）：应走 .custom existential 路径且行为正确
  private final class CustomBitmap: Bitmap {
    private var bytes: [UInt8]
    let count: Int

    init(_ capacity: Int) {
      self.count = capacity
      self.bytes = Array(repeating: 0, count: (capacity + 7) / 8)
    }

    func set(value: Bool, for index: Int) {
      guard count > index else { return }
      let byte = index / 8
      let bit = UInt8(index % 8)
      if value {
        bytes[byte] |= 1 << bit
      } else {
        bytes[byte] &= ~(1 << bit)
      }
    }

    func get(for index: Int) -> Bool? {
      guard count > index else { return nil }
      return (bytes[index / 8] & (1 << UInt8(index % 8))) != 0
    }
  }

  func testCustomBitmapPath() {
    let bloom = BloomFilter(hashCount: 6,
                            bitmap: CustomBitmap(100_000),
                            hasher: DefaultHasher())
    for i in 0..<500 {
      bloom.add("custom-bitmap-\(i)")
    }
    for i in 0..<500 {
      XCTAssertTrue(bloom.contains("custom-bitmap-\(i)"))
    }
    XCTAssertFalse(bloom.contains("not-present"))
  }

  func testCustomHasherAndBitmapPath() {
    let bloom = BloomFilter(hashCount: 6,
                            bitmap: CustomBitmap(100_000),
                            hasher: CustomFNVHasher())
    bloom.add("both")
    XCTAssertTrue(bloom.contains("both"))
    XCTAssertFalse(bloom.contains("neither"))
  }

}
