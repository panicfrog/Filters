//
//  MurmurHash3.swift
//  
//
//  Created by 叶永平 on 2023/3/15.
//

import Foundation
#if canImport(Cmurmur3)
import Cmurmur3
#endif


// 实现了MurmurHash3算法
//
// 该算法是一种非加密型哈希算法，它的特点是速度快，对于小数据块计算很快，而且对于哈希碰撞的情况也很少。
public enum MurmurHash3 {

  /// wrap MurmurHash3_x86_32 to swift
  /// - Parameters:
  ///   - data: data
  ///   - seed: seed
  /// - Returns: hash value
    public static func x86_32(_ data: Data, seed: UInt32) -> UInt32 {
      let len = Int32(data.count)
      return data.withUnsafeBytes { dataPtr in
        var result: UInt32 = 0
        let buffer: UnsafePointer<UInt8> = dataPtr.baseAddress!.assumingMemoryBound(to: UInt8.self)
        MurmurHash3_x86_32(buffer, len, seed, &result)
        return result
      }
    }

  /// 作用域借用版本：直接在原始字节上计算，零拷贝、零分配
  /// - Parameters:
  ///   - data: 借用的字节缓冲区
  ///   - seed: seed
  /// - Returns: hash value
  public static func x86_32(_ data: UnsafeRawBufferPointer, seed: UInt32) -> UInt32 {
    var result: UInt32 = 0
    MurmurHash3_x86_32(data.baseAddress, Int32(data.count), seed, &result)
    return result
  }

  /// wrap MurmurHash3_x64_128 to swift
  /// - Parameters:
  ///   - data: data
  ///   - seed: seed
  /// - Returns: hash value
  public static func x64_128(_ data: Data, seed: UInt32) -> UInt64 {
    let len = Int32(data.count)
    return data.withUnsafeBytes { dataPtr in
      var result: UInt64 = 0
      let buffer: UnsafePointer<UInt8> = dataPtr.baseAddress!.assumingMemoryBound(to: UInt8.self)
      MurmurHash3_x64_128(buffer, len, seed, &result)
      return result
    }
  }

  /// 作用域借用版本：直接在原始字节上计算，零拷贝、零分配
  public static func x64_128(_ data: UnsafeRawBufferPointer, seed: UInt32) -> UInt64 {
    var result: UInt64 = 0
    MurmurHash3_x64_128(data.baseAddress, Int32(data.count), seed, &result)
    return result
  }

  /// wrap c MurmurHash3_x86_128 to swift
  /// - Parameters:
  ///   - data: data
  ///   - seed: seed
  /// - Returns: hash value
  public static func x86_128(_ data: Data, seed: UInt32) -> UInt64 {
    let len = Int32(data.count)
    return data.withUnsafeBytes { dataPtr in
      var result: UInt64 = 0
      let buffer: UnsafePointer<UInt8> = dataPtr.baseAddress!.assumingMemoryBound(to: UInt8.self)
      MurmurHash3_x86_128(buffer, len, seed, &result)
      return result
    }
  }

  /// 作用域借用版本：直接在原始字节上计算，零拷贝、零分配
  public static func x86_128(_ data: UnsafeRawBufferPointer, seed: UInt32) -> UInt64 {
    var result: UInt64 = 0
    MurmurHash3_x86_128(data.baseAddress, Int32(data.count), seed, &result)
    return result
  }

}
