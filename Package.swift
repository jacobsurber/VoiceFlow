// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Whisp",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/Alamofire/Alamofire.git", from: "5.10.2"),
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.15.0"),
    ],
    targets: [
        .target(
            name: "WhispUninstallerCore",
            path: "UninstallerCore"
        ),
        .executableTarget(
            name: "Whisp",
            dependencies: ["Alamofire", "WhisperKit"],
            path: "Sources",
            exclude: ["VersionInfo.swift.template"],
            resources: [
                .process("Assets.xcassets"),
                .copy("verify_parakeet.py"),
                .copy("ml_daemon.py"),
                .copy("ml"),
                // Bundle additional resources like uv binary and lock files
                .copy("Resources"),
            ]
        ),
        .executableTarget(
            name: "WhispUninstaller",
            dependencies: ["WhispUninstallerCore"],
            path: "Uninstaller"
        ),
        .testTarget(
            name: "WhispTests",
            dependencies: ["Whisp"],
            path: "Tests",
            exclude: ["README.md", "test_parakeet_transcribe.py", "__Snapshots__"]
        ),
        .testTarget(
            name: "WhispUninstallerCoreTests",
            dependencies: ["WhispUninstallerCore"],
            path: "UninstallerTests"
        ),
    ]
)
