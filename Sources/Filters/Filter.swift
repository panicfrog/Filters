//
//  Filter.swift
//
//
//  Created by mac studio on 2023/3/18.
//
import Foundation

public protocol FilterElement {
  /// 元素的字节内容（每次调用会分配并拷贝，仅为兼容保留；
  /// 哈希与查询等只读访问请优先实现 `withUnsafeBytes`）
  func data() -> Data

  /// 以作用域借用（borrowing）方式访问元素字节：`body` 执行期间指针有效，
  /// 不产生任何中间拷贝或分配。`body` 不得让指针逃逸。
  @discardableResult
  func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R
}

extension FilterElement {
  /// 默认实现：经 `data()` 桥接（有一次拷贝）。
  /// 只实现了 `data()` 的既有 conformer 自动获得该行为。
  @discardableResult
  public func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
    try data().withUnsafeBytes(body)
  }
}

extension String: FilterElement {
  public func data() -> Data {
    data(using: .utf8)!
  }

  /// 零拷贝：原生字符串（含小字符串）直接借用其 UTF-8 存储。
  /// 仅桥接自 NSString 等非连续存储的罕见情形回退到 `data()`。
  @discardableResult
  public func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
    if let result = try utf8.withContiguousStorageIfAvailable({
      try body(UnsafeRawBufferPointer($0))
    }) {
      return result
    }
    return try data().withUnsafeBytes(body)
  }
}

extension Data: FilterElement {
  public func data() -> Data {
    self
  }
}

public protocol Filter {
    func add(_ element: FilterElement)
    func contains(_ element: FilterElement) -> Bool
}
