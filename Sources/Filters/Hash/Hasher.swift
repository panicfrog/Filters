//
//  Hasher.swift
//
//
//  Created by 叶永平 on 2023/3/17.
//

import Foundation

public protocol Hasher {
  associatedtype I: FixedWidthInteger

  /// 基于 `Data` 的哈希（每次调用经 `withUnsafeBytes` 借用读取，本身无字节拷贝；
  /// 但构造 `Data` 的成本由调用方承担）。作为协议的硬性 requirement 保留，
  /// 只实现该方法的既有 conformer 仍可直接工作。
  func hashValues(_ data: Data, seed: UInt32) -> I

  /// 基于作用域借用缓冲区的哈希：直接在原始字节上计算，零拷贝、零分配。
  /// `data` 仅在本次调用内有效。
  func hashValues(_ data: UnsafeRawBufferPointer, seed: UInt32) -> I
}

extension Hasher {
  /// 未提供借用版本的 conformer 的桥接实现：复制一份 `Data` 再走
  /// `hashValues(_:Data, seed:)`（有一次拷贝，仅为兼容保留）。
  public func hashValues(_ data: UnsafeRawBufferPointer, seed: UInt32) -> I {
    let copy = data.baseAddress.map { Data(bytes: $0, count: data.count) } ?? Data()
    return hashValues(copy, seed: seed)
  }
}

public final class DefaultHasher: Hasher {
  public typealias I = UInt32
  public func hashValues(_ data: Data, seed: UInt32) -> I {
    MurmurHash3.x86_32(data, seed: seed)
  }
  public func hashValues(_ data: UnsafeRawBufferPointer, seed: UInt32) -> I {
    MurmurHash3.x86_32(data, seed: seed)
  }
}

public final class Xxhasher: Hasher {
  public typealias I = UInt32
  public func hashValues(_ data: Data, seed: UInt32) -> I {
    XXH.xxh32(data, seed: seed)
  }
  public func hashValues(_ data: UnsafeRawBufferPointer, seed: UInt32) -> I {
    XXH.xxh32(data, seed: seed)
  }
}
