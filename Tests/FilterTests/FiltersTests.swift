import XCTest
@testable import Filters

/// Read text file line by line in efficient way
public class LineReader {
  public let path: String
  private let trimmed: Bool
  
  fileprivate let file: UnsafeMutablePointer<FILE>!
  
  init?(path: String, trimmed: Bool = true) {
    self.path = path
    self.trimmed = trimmed
    file = fopen(path, "r")
    guard file != nil else { return nil }
  }
  
  public var nextLine: String? {
    var line: UnsafeMutablePointer<CChar>?
    var linecap: Int = 0
    defer { free(line) }
    if trimmed {
      guard getline(&line, &linecap, file) > 0 else { return nil }
      return String(cString: line!).trimmingCharacters(in: .newlines)
    } else {
      return getline(&line, &linecap, file) > 0 ? String(cString: line!) : nil
    }
  }
  
  deinit {
    fclose(file)
  }
}

extension LineReader: Sequence {
   public func makeIterator() -> AnyIterator<String> {
      return AnyIterator<String> {
         return self.nextLine
      }
   }
}

final class FiltersTests: XCTestCase {
  func testMurmur3() throws {
    let sum32 = MurmurHash3.x86_32("Hello, world".data(using: .utf8)!, seed: 0)
    let sum64 = MurmurHash3.x64_128("Hello, world".data(using: .utf8)!, seed: 0)
    let sum128 = MurmurHash3.x86_128("Hello, world".data(using: .utf8)!, seed: 0)
    print("sum with 'hello, world', sum32: \(sum32), sum64: \(sum64), sum128: \(sum128)")
    XCTAssertEqual(sum32, 1785891924)
    XCTAssertEqual(sum64, 16992797472532904308)
    XCTAssertEqual(sum128, 16509527251599854760)
  }
  func testBloomFilter() throws {
    let bloom = BloomFilterBuilder.default
      .with(maxElements: 5)
      .build()
    bloom.add("Hello, world")
    XCTAssertEqual(bloom.contains("Hello, world"), true)
    XCTAssertEqual(bloom.contains("bloom"), false)
    bloom.add("bloom")
    XCTAssertEqual(bloom.contains("bloom"), true)
  }
  
  func testBloomBuilder() throws {
    let bb1 = BloomFilterBuilder.default
    let bb2 = BloomFilterBuilder.default
    XCTAssertTrue(bb1 !== bb2)
  }
  
  func testOverflow() throws {
    let bloom = BloomFilterBuilder.default
      .with(maxElements: 50)
      .build()
    bloom.add("Hello, world")
    XCTAssertEqual(bloom.contains("Hello, world"), true)
  }
  
  func testBigCollectionMurmur3() throws {
    let max = 30000
    let bloom = BloomFilterBuilder.default
      .with(maxElements: max, falsePositiveRate: 0.00001)
      .build()
    for i in 0..<max {
      bloom.add("\(i)")
      XCTAssertEqual(bloom.contains("\(i + 1)"), false)
    }
    for i in 0..<max {
      XCTAssertEqual(bloom.contains("\(i)"), true)
    }
    XCTAssertEqual(bloom.contains("\(max)"), false)
  }
  
  func testBigCollectionXXH() throws {
    let max = 30000
    let bloom = BloomFilterBuilder.default
      .with(maxElements: max, falsePositiveRate: 0.00001)
      .with(hasher: Xxhasher())
      .build()
    for i in 0..<max {
      bloom.add("\(i)")
      XCTAssertEqual(bloom.contains("\(i + 1)"), false)
    }
    for i in 0..<max {
      XCTAssertEqual(bloom.contains("\(i)"), true)
    }
    XCTAssertEqual(bloom.contains("\(max)"), false)
  }
  
  func testUniqKeys() throws {
    let max = 30000
    let bloom = BloomFilterBuilder.default
      .with(maxElements: max, falsePositiveRate: 0.00001)
      .build()
    let path = Bundle.module.url(forResource: "keys", withExtension: "txt")
    guard let path, let file = LineReader(path: path.relativePath) else {
      return
    }
    for line in file {
//      print(line)
      XCTAssertFalse(bloom.contains(line), "expect not contains \(line)")
      bloom.add(line)
    }
    for line in file {
      XCTAssertTrue(bloom.contains(line), "expect contains \(line)")
    }
  }
  
  
  func testMmapBitmap() throws {
    let max = 30000
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("bloom-\(UUID().uuidString).cache")
    defer { try? FileManager.default.removeItem(at: url) }
    let bloom = BloomFilterBuilder.default
      .with(maxElements: max)
      .with { m in
        try! MmapBitmap(m, path: url)
      }.build()
    for i in 0..<max {
      bloom.add("\(i)")
      XCTAssertEqual(bloom.contains("\(i + 1)"), false)
    }
    for i in 0..<max {
      XCTAssertEqual(bloom.contains("\(i)"), true)
    }
    XCTAssertEqual(bloom.contains("\(max)"), false)
  }
    
  func testSafetyBigCollection() throws {
      let max = 30000
      let bloom = BloomFilterBuilder.default
        .with(maxElements: max)
        .with(safety: true)
        .build()
      for i in 0..<max {
        bloom.add("\(i)")
        XCTAssertEqual(bloom.contains("\(i + 1)"), false)
      }
      for i in 0..<max {
        XCTAssertEqual(bloom.contains("\(i)"), true)
      }
      XCTAssertEqual(bloom.contains("\(max)"), false)
    }

  // MARK: - Bitmap set(value: false) tests

  /// indices 覆盖了字内偏移 0、字边界（63/64/127/128）以及首尾位置
  private static let bitmapTestIndices = [0, 1, 5, 10, 11, 63, 64, 65, 127, 128, 129, 199]

  func testCompressedBitmapClearBit() {
    let bitmap = CompressedBitmap(200)
    // 初始为 0 的位，set(false) 后应保持 0（XOR 实现会错误地翻成 1）
    for i in Self.bitmapTestIndices {
      bitmap.set(value: false, for: i)
      XCTAssertEqual(bitmap.get(for: i), false, "index \(i) should remain unset")
    }
    // 已置 1 的位，set(false) 后应清 0
    for i in Self.bitmapTestIndices {
      bitmap.set(value: true, for: i)
    }
    for i in Self.bitmapTestIndices {
      bitmap.set(value: false, for: i)
      XCTAssertEqual(bitmap.get(for: i), false, "index \(i) should be cleared")
    }
  }

  func testCompressedBitmapClearDoesNotAffectNeighbors() {
    let bitmap = CompressedBitmap(128)
    bitmap.set(value: true, for: 10)
    // 清除相邻的、本就为 0 的位 11，不应影响位 10
    bitmap.set(value: false, for: 11)
    XCTAssertEqual(bitmap.get(for: 11), false)
    XCTAssertEqual(bitmap.get(for: 10), true)
  }

  func testMmapBitmapClearBit() throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("mmap-bitmap-\(UUID().uuidString).cache")
    defer { try? FileManager.default.removeItem(at: url) }
    let bitmap = try MmapBitmap(200, path: url)
    // 初始为 0 的位，set(false) 后应保持 0（XOR 实现会错误地翻成 1）
    for i in Self.bitmapTestIndices {
      bitmap.set(value: false, for: i)
      XCTAssertEqual(bitmap.get(for: i), false, "index \(i) should remain unset")
    }
    // 已置 1 的位，set(false) 后应清 0
    for i in Self.bitmapTestIndices {
      bitmap.set(value: true, for: i)
    }
    for i in Self.bitmapTestIndices {
      bitmap.set(value: false, for: i)
      XCTAssertEqual(bitmap.get(for: i), false, "index \(i) should be cleared")
    }
  }

  func testMmapBitmapClearDoesNotAffectNeighbors() throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("mmap-bitmap-\(UUID().uuidString).cache")
    defer { try? FileManager.default.removeItem(at: url) }
    let bitmap = try MmapBitmap(128, path: url)
    bitmap.set(value: true, for: 10)
    bitmap.set(value: false, for: 11)
    XCTAssertEqual(bitmap.get(for: 11), false)
    XCTAssertEqual(bitmap.get(for: 10), true)
  }

}
