import XCTest
@testable import Filters

/// 作用域借用路径 vs 旧拷贝路径的 A/B 基准。
///
/// 两条路径使用完全相同的参数（k=14、同样的 CompressedBitmap 大小、同样的
/// `any Hasher` 动态派发），唯一差异是旧路径每次 add/contains 会产生：
///   1. 一次 String → Data 的 UTF-8 编码分配（element.data()）
///   2. 一次 [Int] 结果数组分配（hashValues）
/// 新路径全程作用域借用，零中间分配。
final class BorrowingBenchmarks: XCTestCase {

  /// 复刻引入作用域借用之前的 BloomFilter 实现
  private final class LegacyBloomFilter: Filter {
    private let bitmap: CompressedBitmap
    private let hashCount: Int
    private let hasher: any Hasher

    init(bitmap: CompressedBitmap, hashCount: Int, hasher: any Hasher) {
      self.bitmap = bitmap
      self.hashCount = hashCount
      self.hasher = hasher
    }

    func add(_ element: FilterElement) {
      let data = element.data()                       // 1 次 String→Data 分配
      let locations = hashValues(data)                // 1 次 [Int] 分配
      for location in locations {
        bitmap.set(value: true, for: location)
      }
    }

    func contains(_ element: FilterElement) -> Bool {
      let data = element.data()                       // 1 次 String→Data 分配
      let hashes = hashValues(data)                   // 1 次 [Int] 分配
      for hash in hashes where bitmap.get(for: hash) == false {
        return false
      }
      return true
    }

    private func hashValues(_ data: Data) -> [Int] {
      var hashValues = Array(repeating: 0, count: hashCount)
      let bitsCount = Int64(bitmap.count)
      for i in 0..<hashCount {
        let hash = hasher.hashValues(data, seed: UInt32(i))
        hashValues[i] = Int(abs(Int64(hash)) % bitsCount)
      }
      return hashValues
    }
  }

  private let keyCount = 100_000
  private let hashCount = 14
  private let mnRate = 20

  private lazy var keys: [String] = (0..<keyCount).map {
    "https://example.com/catalog/items/page/\($0)/detail?ref=feed&lang=zh"
  }

  private func makeNew(_ hasher: any Hasher) -> Filter {
    BloomFilter(hashCount: hashCount,
                bitmap: CompressedBitmap(keyCount * mnRate),
                hasher: hasher)
  }

  private func makeLegacy(_ hasher: any Hasher) -> Filter {
    LegacyBloomFilter(bitmap: CompressedBitmap(keyCount * mnRate),
                      hashCount: hashCount,
                      hasher: hasher)
  }

  /// 只用「全部命中」的正例查询，保证两条路径的哈希次数完全一致，
  /// 差异仅来自中间分配
  private func drive(_ bloom: Filter) {
    for key in keys {
      bloom.add(key)
    }
    var hits = 0
    for key in keys where bloom.contains(key) {
      hits += 1
    }
    if hits != keyCount {
      XCTFail("expected all keys to hit, got \(hits)")
    }
  }

  // MARK: - MurmurHash3（默认 hasher）

  func testBenchLegacyMurmur() {
    let bloom = makeLegacy(DefaultHasher())
    measure { drive(bloom) }
  }

  func testBenchBorrowedMurmur() {
    let bloom = makeNew(DefaultHasher())
    measure { drive(bloom) }
  }

  // MARK: - XXH32

  func testBenchLegacyXXH() {
    let bloom = makeLegacy(Xxhasher())
    measure { drive(bloom) }
  }

  func testBenchBorrowedXXH() {
    let bloom = makeNew(Xxhasher())
    measure { drive(bloom) }
  }

}
