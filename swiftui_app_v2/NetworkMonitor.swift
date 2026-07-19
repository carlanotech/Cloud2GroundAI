//
//  NetworkMonitor.swift
//  Cloud to Ground AI — v0.2
//
//  Wraps NWPathMonitor and updates BridgeStatus.networkOnline. NWPathMonitor
//  is event-driven (kqueue-backed) — satisfies L2-BRG-003 / L2-PWR-002
//  efficiency by not busy-polling.
//
//  Implements: L2-NET-001 (connectivity state detection).
//

import Combine
import Foundation
import Network

@MainActor
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.carlano.c2g.networkmonitor",
                                     qos: .utility)
    private var started = false

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        monitor.pathUpdateHandler = { path in
            let online = (path.status == .satisfied)
            Task { @MainActor in
                BridgeStatus.shared.networkOnline = online
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
