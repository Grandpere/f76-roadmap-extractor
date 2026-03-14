// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ocr",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "CalendarOCR",
            targets: ["CalendarOCR"]
        ),
        .executable(
            name: "ocr",
            targets: ["ocr"]
        ),
        .executable(
            name: "ocr-ui",
            targets: ["ocr-ui"]
        ),
        .executable(
            name: "F76RoadmapExtractor",
            targets: ["ocr-ui"]
        ),
    ],
    targets: [
        .target(
            name: "CalendarOCR"
        ),
        .executableTarget(
            name: "ocr",
            dependencies: ["CalendarOCR"]
        ),
        .executableTarget(
            name: "ocr-smoketests",
            dependencies: ["CalendarOCR"]
        ),
        .executableTarget(
            name: "ocr-ui",
            dependencies: ["CalendarOCR"],
            resources: [
                .process("Resources")
            ]
        ),
    ]
)
