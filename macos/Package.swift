// swift-tools-version:5.10
// App IQOS Monitor para macOS (SwiftUI + CoreBluetooth).
// IqosCore tem o protocolo e a contagem, sem dependências de interface,
// e é o mesmo comportamento de iqos_monitor/protocol.py e tracker.py.

import PackageDescription

let package = Package(
    name: "IqosMonitor",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "IqosMonitor", targets: ["IqosMonitor"]),
    ],
    targets: [
        .target(name: "IqosCore"),
        .executableTarget(name: "IqosMonitor", dependencies: ["IqosCore"]),
        .testTarget(name: "IqosCoreTests", dependencies: ["IqosCore"]),
    ]
)
