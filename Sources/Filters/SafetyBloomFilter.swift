//
//  SafetyBloomFilter.swift
//
//  Created by mac studio on 2023/3/18.
//

import Foundation

final class SafetyBloomFilter: Filter {

    private var bitmap: Bitmap
    private let hashCount: Int
    private let hasher: any Hasher
    private let queue = DispatchQueue(label: "github.io.panicfrog.BloomFilter.SafetyBloomFilter",
                                      attributes: .concurrent)

    /// create bloom filter
    /// - Parameters:
    ///   - bitmap: bitmap
    ///   - hashCount: bits count per element
    ///   - hasher: hasher
    init(bitmap: Bitmap, hashCount: Int, hasher: any Hasher) {
        self.bitmap = bitmap
        self.hashCount = hashCount
        self.hasher = hasher
    }

    /// add element to bloom filter
    ///
    /// 元素字节全程作用域借用（在 barrier 任务内完成哈希与置位），
    /// 无中间 `Data` / `[Int]` 分配。
    /// - Parameter element: element
    func add(_ element: FilterElement) {
        let bitmap = self.bitmap
        let hashCount = self.hashCount
        let hasher = self.hasher
        queue.async(flags: .barrier) {
            element.withUnsafeBytes { buffer in
                let bitsCount = Int64(bitmap.count)
                for i in 0..<hashCount {
                    let hash = hasher.hashValues(buffer, seed: UInt32(i))
                    bitmap.set(value: true, for: Int(abs(Int64(hash)) % bitsCount))
                }
            }
        }
    }

    /// determine whether the bloom filter contains this element
    ///
    /// 元素字节全程作用域借用，无中间 `Data` / `[Int]` 分配，首个未命中位即返回。
    /// - Parameter element: element
    /// - Returns: result
    func contains(_ element: FilterElement) -> Bool {
        let bitmap = self.bitmap
        let hashCount = self.hashCount
        let hasher = self.hasher
        return queue.sync {
            element.withUnsafeBytes { buffer -> Bool in
                let bitsCount = Int64(bitmap.count)
                for i in 0..<hashCount {
                    let hash = hasher.hashValues(buffer, seed: UInt32(i))
                    if bitmap.get(for: Int(abs(Int64(hash)) % bitsCount)) == false {
                        return false
                    }
                }
                return true
            }
        }
    }

}
