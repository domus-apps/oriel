// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Oriel",
    /* macOS 26+ renders apps linked against an older SDK in the legacy
       compatibility design (old-style traffic lights, pre-Liquid Glass
       chrome). This toolchain stamps the binary's LC_BUILD_VERSION sdk field
       from the deployment target, so the target must be >= 26 for the app
       to get the native current-OS appearance. */
    platforms: [.macOS("26.0")],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.6")
    ],
    targets: [
        .executableTarget(
            name: "Oriel",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/Oriel",
            linkerSettings: [
                /* Sparkle.framework is embedded at Contents/Frameworks by
                   Scripts/bundle.sh; the binary needs the matching rpath.
                   (`swift run` still works: SPM adds the build dir to the
                   rpath list itself.) */
                .unsafeFlags([
                    "-Xlinker", "-rpath",
                    "-Xlinker", "@executable_path/../Frameworks",
                ])
            ]
        ),
        .testTarget(
            name: "OrielTests",
            dependencies: ["Oriel"],
            path: "Tests/OrielTests"
        )
    ]
)
