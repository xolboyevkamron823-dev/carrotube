// swift-tools-version: 5.9
// Swift Package used by Flutter's Swift Package Manager integration (default since
// Flutter 3.3x). CocoaPods users get the same sources through ../carro_native.podspec.

import PackageDescription

let package = Package(
    name: "carro_native",
    platforms: [
        .iOS("15.0")
    ],
    products: [
        .library(name: "carro-native", targets: ["carro_native"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        // Shared C++17 DSP core (core/) + Objective-C++ bridge (MTAudioProcessingTap).
        .target(
            name: "CarroDSP",
            path: "Sources/CarroDSP",
            publicHeadersPath: "include",
            cxxSettings: [
                .define("NDEBUG", .when(configuration: .release)),
                .headerSearchPath("core"),
            ],
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("MediaToolbox"),
                .linkedFramework("CoreMedia"),
                .linkedLibrary("c++"),
            ]
        ),
        .target(
            name: "carro_native",
            dependencies: [
                "CarroDSP",
                .product(name: "FlutterFramework", package: "FlutterFramework"),
            ],
            path: "Sources/carro_native",
            resources: [
                .process("PrivacyInfo.xcprivacy")
            ],
            linkerSettings: [
                .linkedFramework("AVKit"),
                .linkedFramework("MediaPlayer"),
            ]
        ),
    ],
    cxxLanguageStandard: .cxx17
)
