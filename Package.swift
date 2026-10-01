// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Clip",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "Clip",
            targets: ["Clip"]
        )
    ],
    targets: [
        .executableTarget(
            name: "Clip",
            path: "Sources/Clip",
            exclude: ["Resources"]
        )
    ]
)
