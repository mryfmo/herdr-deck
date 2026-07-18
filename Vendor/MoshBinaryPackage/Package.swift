// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HerdDeckMoshBinaries",
    platforms: [.iOS(.v14)],
    products: [
        .library(
            name: "HerdDeckMoshBinaries",
            targets: ["mosh", "Protobuf_C_"]
        )
    ],
    targets: [
        .binaryTarget(
            name: "mosh",
            url: "https://github.com/blinksh/mosh-apple/releases/download/v1.4.0+blink-18.4.5/mosh.xcframework.zip",
            checksum: "d6dce7664ecce1b15931d6b0b8aaf3b1cacebe390669df960fe47318cb0dda05"
        ),
        .binaryTarget(
            name: "Protobuf_C_",
            url: "https://github.com/blinksh/protobuf-apple/releases/download/v3.21.1/Protobuf_C_-static.xcframework.zip",
            checksum: "a74e23890cf2093047544e18e999f493cf90be42a0ebd1bf5d4c0252d7cf377a"
        )
    ]
)
