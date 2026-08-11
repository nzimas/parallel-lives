// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Vascular",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "VascularCore", targets: ["VascularCore"]),
        .executable(name: "Vascular", targets: ["VascularMac"]),
        .executable(name: "VascularCoreChecks", targets: ["VascularCoreChecks"]),
        .executable(name: "VascularMIDIDiagnostics", targets: ["VascularMIDIDiagnostics"]),
    ],
    targets: [
        .target(name: "VascularCore"),
        .executableTarget(
            name: "VascularMac",
            dependencies: ["VascularCore"],
            resources: [
                .copy("Resources/Runtime"),
                .copy("Resources/Orchestra"),
                .copy("Resources/Notices"),
            ]
        ),
        .executableTarget(
            name: "VascularCoreChecks",
            dependencies: ["VascularCore"]
        ),
        .executableTarget(name: "VascularMIDIDiagnostics"),
    ]
)
