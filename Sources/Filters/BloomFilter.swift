//
//  BloomFilter.swift
//
//
//  Created by 叶永平 on 2023/3/17.
//

import Foundation

public final class BloomFilter: Filter {

    /// hasher 的内部表示：内建类型在 init 时归一化为免派发（direct call）的
    /// 闭集 case，热循环中无 witness 表加载；自定义 hasher 落到 existential 兜底。
    private enum HasherImpl {
        case murmur3
        case xxh32
        case custom(any Hasher)
    }

    /// bitmap 的内部表示：同上。内建的具体类型（final class）调用可被内联，
    /// 实测比 existential 派发快一个数量级。
    private enum BitmapImpl {
        case compressed(CompressedBitmap)
        case mmap(MmapBitmap)
        case custom(any Bitmap)
    }

    private let hasherImpl: HasherImpl
    private let bitmapImpl: BitmapImpl
    private let bitsCount: Int
    private let hashCount: Int

    /// create bloom filter
    /// - Parameters:
    ///   - hashCount: bits count per element
    ///   - bitmap: bitmap
    ///   - hasher: hasher
    public init(hashCount: Int, bitmap: Bitmap, hasher: any Hasher) {
        self.hashCount = hashCount
        self.bitsCount = bitmap.count
        if hasher is DefaultHasher {
            self.hasherImpl = .murmur3
        } else if hasher is Xxhasher {
            self.hasherImpl = .xxh32
        } else {
            self.hasherImpl = .custom(hasher)
        }
        if let compressed = bitmap as? CompressedBitmap {
            self.bitmapImpl = .compressed(compressed)
        } else if let mmap = bitmap as? MmapBitmap {
            self.bitmapImpl = .mmap(mmap)
        } else {
            self.bitmapImpl = .custom(bitmap)
        }
    }

    /// add element to bloom filter
    ///
    /// 元素字节全程作用域借用，无中间 `Data` / `[Int]` 分配；
    /// 内建 hasher/bitmap 走免派发快速路径。
    /// - Parameter element: element
    public func add(_ element: FilterElement) {
        element.withUnsafeBytes { buffer in
            let bits = Int64(self.bitsCount)
            for i in 0..<self.hashCount {
                let location: Int
                switch self.hasherImpl {
                case .murmur3:
                    location = Int(Int64(MurmurHash3.x86_32(buffer, seed: UInt32(i))) % bits)
                case .xxh32:
                    location = Int(Int64(XXH.xxh32(buffer, seed: UInt32(i))) % bits)
                case .custom(let hasher):
                    let hash = hasher.hashValues(buffer, seed: UInt32(i))
                    location = Int(abs(Int64(hash)) % bits)
                }
                switch self.bitmapImpl {
                case .compressed(let bitmap): bitmap.set(value: true, for: location)
                case .mmap(let bitmap): bitmap.set(value: true, for: location)
                case .custom(let bitmap): bitmap.set(value: true, for: location)
                }
            }
        }
    }

    /// determine whether the bloom filter contains this element
    ///
    /// 元素字节全程作用域借用，无中间 `Data` / `[Int]` 分配，首个未命中位即返回；
    /// 内建 hasher/bitmap 走免派发快速路径。
    /// - Parameter element: element
    /// - Returns: result
    public func contains(_ element: FilterElement) -> Bool {
        element.withUnsafeBytes { buffer -> Bool in
            let bits = Int64(self.bitsCount)
            for i in 0..<self.hashCount {
                let location: Int
                switch self.hasherImpl {
                case .murmur3:
                    location = Int(Int64(MurmurHash3.x86_32(buffer, seed: UInt32(i))) % bits)
                case .xxh32:
                    location = Int(Int64(XXH.xxh32(buffer, seed: UInt32(i))) % bits)
                case .custom(let hasher):
                    let hash = hasher.hashValues(buffer, seed: UInt32(i))
                    location = Int(abs(Int64(hash)) % bits)
                }
                switch self.bitmapImpl {
                case .compressed(let bitmap):
                    if bitmap.get(for: location) == false { return false }
                case .mmap(let bitmap):
                    if bitmap.get(for: location) == false { return false }
                case .custom(let bitmap):
                    if bitmap.get(for: location) == false { return false }
                }
            }
            return true
        }
    }

}
