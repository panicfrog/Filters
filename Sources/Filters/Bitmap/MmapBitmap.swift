//
//  MmapBitmap.swift
//  
//
//  Created by 叶永平 on 2023/3/21.
//

import Foundation

enum MmapBitmapError: Error {
  case openFileError(Int32)
  case truncateError
  case mmapFailed
}

public final class MmapBitmap: Bitmap {
  public let count: Int
  
  private var fd: Int32?
  private var filePtr: UnsafeMutableRawPointer?
  private var ptr: UnsafeMutablePointer<UInt64>?
  
  public init(_ capacity: Int, path: URL) throws {
    self.count = capacity
    let int64Count = ceil64(capacity)
    let fd = open(path.relativePath, O_RDWR | O_CREAT, S_IRUSR | S_IWUSR)
    guard fd > 0 else {
      throw MmapBitmapError.openFileError(fd)
    }
    let fileSize = int64Count * MemoryLayout<UInt64>.stride
    guard ftruncate(fd, off_t(fileSize)) == 0 else {
      throw MmapBitmapError.truncateError
    }
    let filePtr = mmap(nil, fileSize, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0)
    guard let filePtr, filePtr != MAP_FAILED else {
      throw MmapBitmapError.mmapFailed
    }
    self.fd = fd
    self.filePtr = filePtr
    let ptr = filePtr.bindMemory(to: UInt64.self, capacity: int64Count)
    self.ptr = ptr
  }
  
  deinit {
    guard let filePtr, let ptr, let fd else { return }
    ptr.deinitialize(count: ceil64(count))
    munmap(filePtr, ceil64(count) * MemoryLayout<UInt64>.stride)
    close(fd)
  }
  
  public func set(value: Bool, for index: Int) {
    guard count > index, let ptr else { return }
    let (lct, idx) = locationIndex(index)
    if value {
      ptr.advanced(by: lct).pointee =  ptr.advanced(by: lct).pointee | 1 << idx
    } else {
      ptr.advanced(by: lct).pointee =  ptr.advanced(by: lct).pointee & ~(1 << idx)
    }
  }
  
  public func get(for index: Int) -> Bool? {
    guard count > index, let ptr else { return nil }
    let (lct, idx) = locationIndex(index)
    return !(ptr.advanced(by: lct).pointee & 1 << idx == 0)
  }
  
}
