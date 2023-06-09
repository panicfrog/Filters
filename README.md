# Filter

This is a library for implementing Bloom and Cuckoo filters in Swift. The library provides two filters `BloomFilter` and `CuckooFilter` which can be used to filter data, reduce database access, crawlers, etc.

`CuckooFilter` is under development, details are in [cuckoo_filter branch](https://github.com/panicfrog/Filters/tree/cuckoo_filter)

## Installation

The library can be added as dependency via [swift package manager](https://www.swift.org/package-manager/) or [Cocoapods](https://cocoapods.org/) .

#### SPM

```swift
// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "YourPackage",
    products: [
        .library(name: "YourPackage", targets: ["YourPackage"]),
    ],
    dependencies: [
        .package(url: "https://github.com/panicfrog/Filters.git", from: "0.0.2"),
    ],
    targets: [
        .target(
            name: "YourPackage",
            dependencies: ["Filter"]),
    ]
)
```

#### Xcode

File -> Add packages  https://github.com/panicfrog/Filters.git

### Cocoapods

```ruby
pod 'Filters', '~> 0.0.2'
```



## Usage

```swift
// create bloom filter with `BloomFilterBuilder`
let bloom = BloomFilterBuilder.default
        .with(maxElements: max)   // the maximum number of elements expected to be added
        .with(hasher: Xxhasher()) // default is Murmurhash3_x86_32
        .with(safety: true)       // thread safety
        .build()
// add item to filter
bloom.add("hello")
// determine whether item is comtained in the bloom filter
bloom.contains("hello")
```

you can also use mmap to mapping bloom's bitmap to a file

```swift
// create bloom filter with `BloomFilterBuilder`, that can mapping bitmap to file using mmap
let url = URL(string: "<path your want to mapping>")!
let bloom = BloomFilterBuilder.default
  .with(maxElements: max)
  .with { m in
    try! MmapBitmap(m, path: url)
  }.build()
// add item to filter
bloom.add("item1")
// determine whether item is comtained in the bloom filter
bloom.contains("item1")
```

## API

You can clone the warehouse code, and then use Swift-DocC to produce the api documentation for local preview, and the online documentation is coming soon ...

```shell
swift package --disable-sandbox preview-documentation --target Filter
```

## License

This library is licensed under the MIT License. See the [LICENSE](./LICENSE) file for more details.
