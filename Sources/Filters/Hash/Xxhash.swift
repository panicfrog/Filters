//
//  File.swift
//  
//
//  Created by mac studio on 2023/4/13.
//

import Foundation
#if canImport(Cxxh)
import Cxxh
#endif

public enum XXH {
  public static func xxh32(_ data: Data, seed: UInt32) -> UInt32 {
    let len = data.count
    return data.withUnsafeBytes { dataPtr in
      let buffer: UnsafePointer<UInt8> = dataPtr.baseAddress!.assumingMemoryBound(to: UInt8.self)
#if canImport(Cxxh)
      return XXH_INLINE_XXH32(buffer, len, seed)
#else
      return XXH32(buffer, len, seed)
#endif

    }
  }

  /// 作用域借用版本：直接在原始字节上计算，零拷贝、零分配
  public static func xxh32(_ data: UnsafeRawBufferPointer, seed: UInt32) -> UInt32 {
#if canImport(Cxxh)
    return XXH_INLINE_XXH32(data.baseAddress, data.count, seed)
#else
    return XXH32(data.baseAddress, data.count, seed)
#endif
  }

  public static func xxh64(_ data: Data, seed: UInt64) -> UInt64 {
    let len = data.count
    return data.withUnsafeBytes { dataPtr in
      let buffer: UnsafePointer<UInt8> = dataPtr.baseAddress!.assumingMemoryBound(to: UInt8.self)
#if canImport(Cxxh)
      return XXH_INLINE_XXH64(buffer, len, seed)
#else
      return XXH64(buffer, len, seed)
#endif
    }
  }

  /// 作用域借用版本：直接在原始字节上计算，零拷贝、零分配
  public static func xxh64(_ data: UnsafeRawBufferPointer, seed: UInt64) -> UInt64 {
#if canImport(Cxxh)
    return XXH_INLINE_XXH64(data.baseAddress, data.count, seed)
#else
    return XXH64(data.baseAddress, data.count, seed)
#endif
  }
}
