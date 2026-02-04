// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "EnsoTalk",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "EnsoTalk", targets: ["EnsoTalk"])
    ],
    targets: [
        .executableTarget(
            name: "EnsoTalk",
            path: "Sources/EnsoTalk"
        )
    ]
)
