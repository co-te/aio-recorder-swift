// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AIO",
    platforms: [.iOS(.v16)],
    targets: [
        .executableTarget(
            name: "AIOApp",
            path: "AIO"
        )
    ]
)
