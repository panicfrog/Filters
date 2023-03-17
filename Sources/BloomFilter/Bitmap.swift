//
//  Bitmap.swift
//  
//
//  Created by 叶永平 on 2023/3/17.
//

public protocol Bitmap {
  func `set`(value: Bool, for index: Int)
  func `get`(for index: Int) -> Bool?
  var count: Int { get }
}
