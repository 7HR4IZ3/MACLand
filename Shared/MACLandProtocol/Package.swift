// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "MACLandProtocol",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "MACLandProtocol",
            targets: ["MACLandProtocol"]
        )
    ],
    targets: [
        .target(name: "MACLandProtocol"),
        .testTarget(
            name: "MACLandProtocolTests",
            dependencies: ["MACLandProtocol"]
        )
    ]
)
