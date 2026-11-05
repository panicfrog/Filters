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

}
