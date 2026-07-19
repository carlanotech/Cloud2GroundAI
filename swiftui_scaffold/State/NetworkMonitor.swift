//
//  NetworkMonitor.swift
//  Cloud to Ground AI
//
//  Wraps NWPathMonitor and publishes a NetworkStatus. Detects loss /
//  restoration of connectivity per L2-NET-001 (≤5s budget on CBE).
//
//  NWPathMonitor is event-driven (kqueue-backed) — it satisfies the
//  L2-BRG-003 / L2-PWR-002 efficiency requirement for network detection
//  by not busy-polling.
//

import Combine
import Foundation
import Network

@MainActor
final class NetworkMonitor: ObservableObject {
    @Published private(set) var status: NetworkStatus = .unknown

    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "com.carlano.c2g.networkmonitor")

    init(autostart: Bool = true) {
        self.monitor = NWPathMonitor()
        self.monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.status = (path.status == .satisfied) ? .online : .offline
            }
        }
        if autostart { start() }
    }

    func start() {
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
