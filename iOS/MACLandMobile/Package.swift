// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MACLandMobile",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "MACLandMobile",
            targets: ["MACLandMobile"]
        )
    ],
    targets: [
        .target(
            name: "MACLandMobile",
            exclude: ["MACLandMobileApp.swift"]
        ),
        .testTarget(
            name: "MACLandMobileTests",
            dependencies: ["MACLandMobile"]
        )
    ]
)
