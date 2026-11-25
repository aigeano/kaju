// swift-tools-version:5.10
// Copyright 2026 Sagar Pandey. Licensed under the Apache License 2.0; see LICENSE and NOTICE.
import PackageDescription

let package = Package(
    name: "kaju",
    platforms: [.macOS(.v13)],
    targets: [
        // Logic without UI: messages, safety checks, review store, config, clipboard policy, tmux parsing.
        .target(name: "KajuCore"),
        // The menu-bar app: hotkey, comment input, review panel, terminal adapters.
        .executableTarget(name: "kaju", dependencies: ["KajuCore"]),
        .testTarget(name: "KajuCoreTests", dependencies: ["KajuCore"]),
    ]
)
