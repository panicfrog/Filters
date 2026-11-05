//
//  BloomFilter.swift
//
//
//  Created by 叶永平 on 2023/3/17.
//

import Foundation

public final class BloomFilter: Filter {

    private var bitmap: Bitmap
    private let hashCount: Int
    private let hasher: any Hasher

    /// create bloom filter
    /// - Parameters:
    ///   - hashCount: bits count per element
    ///   - bitmap: bitmap
    ///   - hasher: hasher
    public init(hashCount: Int, bitmap: Bitmap, hasher: any Hasher) {
        self.hashCount = hashCount
        self.bitmap = bitmap
        self.hasher = hasher
    }

    /// add element to bloom filter
    ///
    /// 元素字节全程作用域借用，无中间 `Data` / `[Int]` 分配。
    /// - Parameter element: element
    public func add(_ element: FilterElement) {
        element.withUnsafeBytes { buffer in
            let bitsCount = Int64(bitmap.count)
            for i in 0..<hashCount {
                let hash = hasher.hashValues(buffer, seed: UInt32(i))
                bitmap.set(value: true, for: Int(abs(Int64(hash)) % bitsCount))
            }
        }
    }

    /// determine whether the bloom filter contains this element
    ///
    /// 元素字节全程作用域借用，无中间 `Data` / `[Int]` 分配，首个未命中位即返回。
    /// - Parameter element: element
    /// - Returns: result
    public func contains(_ element: FilterElement) -> Bool {
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
