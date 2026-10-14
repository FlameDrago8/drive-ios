// swift-tools-version: 6.0
//
// DriveUI — skeleton of the iOS-native redesign (see ../README.md).
// Standalone on purpose: it does not import or modify the Drive app target.
// Open this folder in Xcode and use the #Preview canvases, or add the package
// to a scratch app target and show `DriveRedesignRoot()`.

import PackageDescription

let package = Package(
    name: "DriveUI",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "DriveUI", targets: ["DriveUI"])
    ],
    targets: [
        .target(name: "DriveUI")
    ],
    swiftLanguageModes: [.v5]
)
